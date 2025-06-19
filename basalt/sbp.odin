package basalt

import "core:log"

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
