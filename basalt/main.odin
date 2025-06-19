package basalt

import "base:runtime"
import "core:log"
import "core:net"
import "core:thread"
import "core:encoding/endian"
import "core:encoding/json"

RECV_BUFFER_SIZE :: 4096
VERSION          :: "1.8.9"
PACKET_PROTOCOL  :: 47

PORT           :: 25565
ONLINE_PLAYERS :: 0
MAX_PLAYERS    :: 69
MOTD           :: "awesome awesome awesome!!1"

state := State.Handshake

main :: proc() {
	context.logger = log.create_console_logger(.Debug, {.Level})

	listen_socket, listen_err := net.listen_tcp({
		address = net.IP4_Loopback,
		port = PORT,
	})

	if listen_err != nil {
		log.panic("Could not init listen socket:", listen_err)
	}

	defer net.close(listen_socket)

	log.info("Server listening on port", PORT)
	defer log.info("Server stopped listening")

	for {
		client_socket, client_endpoint, accept_err := net.accept_tcp(listen_socket)

		if accept_err != nil {
			log.panic("Could not accept listen socket:", accept_err)
		}

		log.debug("New connection:", client_endpoint)

		thread_data := HandleClientData {
			client_socket = client_socket,
			ctx = context,
		}

		thread.create_and_start_with_poly_data(&thread_data, handle_client)
	}
}

HandleClientData :: struct {
	client_socket: net.TCP_Socket,
	ctx:           runtime.Context, // used for logging
}

handle_client :: proc(thread_data: ^HandleClientData) {
	context = thread_data.ctx
	defer net.close(thread_data.client_socket)

	recv_buffer: [RECV_BUFFER_SIZE]u8

	for {
		bytes_read, read_err := net.recv(thread_data.client_socket, recv_buffer[:])

		if read_err != nil {
			log.error("Could not receive data or client disconnected:", read_err)
			break
		}

		if bytes_read == 0 {
			log.debug("Client disconnected")
			break
		}

		log.debugf("Received %d bytes", bytes_read)
		log.debug(recv_buffer[:bytes_read])

		sbp, sbp_err := sbp_decode(recv_buffer[:bytes_read])
		if sbp_err != nil {
			log.error("Could not parse SBP:", sbp_err)
			break
		}

		log.debug(sbp)

		switch p in sbp {
		case SBP_Handshake:
			state = p.next_state
		case SBP_Request:
			handshake_response := HandshakeResponse {
				version = {
					name     = VERSION,
					protocol = PACKET_PROTOCOL,
				},
				players = {
					online = ONLINE_PLAYERS,
					max    = MAX_PLAYERS,
				},
				description = {
					text = MOTD,
				},
			}
			json_str, json_err := json.marshal(handshake_response)
			if json_err != nil {
				log.error("Could not marshal handshake response:", json_err)
				break
			}
			res := CBP_Response {
				json = string(json_str),
			}
			log.debug(res)
			res_packet := cbp_encode(res)
			
			bytes_sent, send_err := net.send_tcp(thread_data.client_socket, res_packet[:])
			if send_err != nil {
				log.error("Could not send data:", send_err)
				break
			}

			log.debugf("Sending %d bytes", bytes_sent)
			log.debug(res_packet[:bytes_sent])
		}
	}
}

PacketRaw :: struct {
	length: varint,
	id:     varint,
	buffer: []u8,
}

varint :: i32

cbp_encode :: proc(cbp: ClientBoundPacket) -> (buffer: []u8) {
	buffer_dynamic: [dynamic]u8

	switch p in cbp {
	case CBP_Response:
		append(&buffer_dynamic, 0x00)
		str := encode_string(p.json)
		defer delete(str)
		append(&buffer_dynamic, ..str)
	}

	buffer_length := encode_varint(i32(len(buffer_dynamic)))
	defer delete(buffer_length)
	#reverse for pl in buffer_length {
		inject_at_elem(&buffer_dynamic, 0, pl)
	}

	buffer = buffer_dynamic[:]

	return
}

encode_string :: proc(value: string) -> (buffer: []u8) {
	buffer_dynamic: [dynamic]u8

	length := encode_varint(i32(len(value)))
	defer delete(length)
	append(&buffer_dynamic, ..length)

	append(&buffer_dynamic, ..transmute([]u8)value)

	buffer = buffer_dynamic[:]

	return
}

encode_varint :: proc(value: varint) -> (buffer: []u8) {
	buffer_dynamic: [dynamic]u8
	val := cast(u32)value

	for {
		byte_val := cast(u8)(val & 0x7F)
		val >>= 7
		
		if val != 0 {
			byte_val |= 0x80
		}
		
		append(&buffer_dynamic, byte_val)
		
		if val == 0 {
			break
		}
	}

	buffer = buffer_dynamic[:]

	return
}

// CBP: server -> client
ClientBoundPacket :: union { // add #no_nil
	CBP_Response,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Response
CBP_Response :: struct {
	json: string,
}

DecodeError :: union #shared_nil {
	VarIntError,
	StringError,
	EndianError,
}

sbp_decode :: proc(buffer: []u8) -> (sbp: ServerBoundPacket, err: DecodeError) {
	offset: uint = 0

	packet_raw := PacketRaw {
		length = decode_varint(buffer, &offset) or_return,
		id     = decode_varint(buffer, &offset) or_return,
		buffer = buffer[offset:],
	}

	log.debug("packet_raw", packet_raw)

	packet_offset: uint = 0

	#partial switch state {
	case .Handshake:
		switch packet_raw.id {
		case 0x00:
			sbp = SBP_Handshake {
				protocol_version = decode_varint(packet_raw.buffer, &packet_offset) or_return,
				server_address   = decode_string(packet_raw.buffer, &packet_offset) or_return,
				server_port      = decode_u16(packet_raw.buffer, &packet_offset) or_return,
				next_state       = State(decode_varint(packet_raw.buffer, &packet_offset) or_return),
			}
		}
	case .Status:
		switch packet_raw.id {
		case 0x00:
			sbp = SBP_Request{}
		}
	}

	return
}

decode_check_offset :: proc(buffer: []u8, offset: uint) -> (err: DecodeError) {
	if offset >= uint(len(buffer)) {
		err = .InvalidOffset
	}

	return
}

decode_u16 :: proc(buffer: []u8, offset: ^uint) -> (value: u16, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	ok: bool
	value, ok = endian.get_u16(buffer[offset^:][:size_of(u16)], .Big)

	if !ok {
		err = .InvalidEndian
		return
	}

	offset^ += size_of(u16)

	return
}

decode_string :: proc(buffer: []u8, offset: ^uint) -> (value: string, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	length := decode_varint(buffer, offset) or_return

	// if offset^ + uint(length) > len(buffer) {
	// 	err = .InvalidSize
	// 	return
	// }

	value = string(buffer[offset^:][:length])
	offset^ += uint(length)

	return
}

decode_varint :: proc(buffer: []u8, offset: ^uint) -> (value: varint, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	offset_init := offset^
	position := 0
	value_raw: u32 = 0

	for i in offset_init..<uint(len(buffer)) {
		current_byte := buffer[i]
		offset^ += 1
		value_raw |= cast(u32)(current_byte & 0x7F) << cast(u32)(position * 7)

		if (current_byte & 0x80) == 0 {
			value = cast(i32)value_raw
			return
		}

		position += 1

		if position >= 5 {
			err = .InvalidSize
			return
		}
	}

	err = .Incomplete
	return
}

VarIntError :: enum {
	InvalidOffset,
	InvalidSize,
	Incomplete,
}

StringError :: enum {
	InvalidLength,
}

EndianError :: enum {
	InvalidEndian,
}

// SBP: client -> server
ServerBoundPacket :: union #no_nil {
	SBP_Handshake,
	SBP_Request,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Handshaking
SBP_Handshake :: struct {
	protocol_version: varint,
	server_address:   string,
	server_port:      u16,
	next_state:       State,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Request
SBP_Request :: struct {}

State :: enum varint {
	Handshake = 0,
	Status    = 1, // https://minecraft.wiki/w/Protocol?oldid=2772100#Status
	Login     = 2, // https://minecraft.wiki/w/Protocol?oldid=2772100#Login
	Play      = 3,
}

HandshakeResponse :: struct {
	version: struct {
		name:     string,
		protocol: int,
	},
	players: struct {
		online: int,
		max:    int,
	},
	description: struct {
		text: string,
	},
	// favicon: string,
}
