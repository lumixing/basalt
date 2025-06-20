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
			defer delete(res_packet)
			
			bytes_sent, send_err := net.send_tcp(thread_data.client_socket, res_packet[:])
			if send_err != nil {
				log.error("Could not send data:", send_err)
				break
			}

			log.debugf("Sending %d bytes", bytes_sent)
			log.debug(res_packet[:bytes_sent])
		case SBP_Ping:
			res := CBP_Pong {
				payload = p.payload,
			}
			log.debug(res)
			res_packet := cbp_encode(res)
			defer delete(res_packet)
			
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
