package basalt

import "core:fmt"
import "core:net"
import "core:thread"
import "core:encoding/json"

RECV_BUFFER_SIZE :: 4096
VERSION          :: "1.8.9"
PACKET_PROTOCOL  :: 47

server_config := server_config_init()

main :: proc() {
	log_init()
	defer log_free()

	defer clients_free()
	defer delete(packets)

	listen_socket, listen_err := net.listen_tcp({
		address = net.IP4_Any,
		port = int(server_config.port),
	})

	lassert(listen_err == nil, "could not init listen socket:", listen_err)

	defer net.close(listen_socket)

	linfo("server listening on port", server_config.port)
	defer linfo("server stopped listening")

	thread.create_and_start_with_poly_data(listen_socket, handle_listen)

	ui_init()
	defer ui_deinit()

	ui_loop()
}

handle_listen :: proc(listen_socket: net.TCP_Socket) {
	ldebug("listening for clients...")
	defer ldebug("not listening for clients...")
	for {
		client_socket, client_endpoint, accept_err := net.accept_tcp(listen_socket)
		lassert(accept_err == nil, "could not accept listen socket:", accept_err, level = .ERROR)

		client_ip, client_is_ipv4 := client_endpoint.address.(net.IP4_Address)
		lassert(client_is_ipv4, "client", client_endpoint, "is not ipv4!")

		client_end := ClientEndpoint {
			ip0  = client_ip[0],
			ip1  = client_ip[1],
			ip2  = client_ip[2],
			ip3  = client_ip[3],
			port = u16(client_endpoint.port),
		}

		ldebug("client", u64(client_end), "connected")

		lassert(client_end not_in clients, "client", client_endpoint, client_end, "is already connected!")
		clients[client_end] = new_clone(Client {
			state = .Handshake,
		})

		thread.create_and_start_with_poly_data2(client_socket, client_end, handle_client)
	}
}

handle_client :: proc(client_socket: net.TCP_Socket, client_end: ClientEndpoint) {
	defer net.close(client_socket)

	recv_buffer: [RECV_BUFFER_SIZE]u8

	for {
		bytes_read, recv_err := net.recv(client_socket, recv_buffer[:])

		lassert(recv_err == nil, "could not recv data:", recv_err) or_break

		if bytes_read == 0 {
			ldebug("client", u64(client_end), "disconnected")
			lassert(client_end in clients, "client is not connected!")
			delete_key(&clients, client_end)
			break
		}

		ldebug(recv_buffer[:bytes_read])

		offset: uint = 0
		packet := Packet {
			length = decode_varint(recv_buffer[:bytes_read], &offset).?,
			id     = decode_varint(recv_buffer[:bytes_read], &offset).?,
			data   = recv_buffer[offset:bytes_read]
		}

		ldebug(packet)

		clients[client_end].packets_recv += 1
		clients[client_end].bytes_recv += uint(bytes_read)

		#partial switch clients[client_end].state {
		case .Handshake:
			switch packet.id {
			case 0x00:
				sbp := sbp_decode(SBP_Handshake, packet.data)
				append(&packets, ServerBoundPacket(sbp))

				clients[client_end].state = sbp.next_state
			}
		case .Status:
			switch packet.id {
			case 0x00:
				sbp := sbp_decode(SBP_Request, packet.data)
				append(&packets, ServerBoundPacket(sbp))
				
				handshake_response := HandshakeResponse {
					version = {
						name     = VERSION,
						protocol = PACKET_PROTOCOL,
					},
					players = {
						online = 0,
						max    = int(server_config.max_players),
					},
					description = {
						text = server_config.motd,
					},
				}
				json_str, json_err := json.marshal(handshake_response)
				lassert(json_err == nil, "could not marshal handshake response:", json_err) or_break

				cbp := CBP_Response {
					json = string(json_str),
				}
				append(&packets, ClientBoundPacket(cbp))
				
				buf := packet_encode(cbp_encode(cbp))
				defer delete(buf)
				ldebug("sent", buf)

				bytes_sent, send_err := net.send_tcp(client_socket, buf[:])
				lassert(send_err == nil, "could not send data:", send_err) or_break
				clients[client_end].packets_sent += 1
				clients[client_end].bytes_sent += uint(bytes_sent)
			case 0x01:
				sbp := sbp_decode(SBP_Ping, packet.data)
				append(&packets, ServerBoundPacket(sbp))

				cbp := CBP_Pong {
					payload = sbp.payload,
				}
				append(&packets, ClientBoundPacket(cbp))
				
				buf := packet_encode(cbp_encode(cbp))
				defer delete(buf)
				ldebug("sent", buf)

				bytes_sent, send_err := net.send_tcp(client_socket, buf[:])
				lassert(send_err == nil, "could not send data:", send_err) or_break
				clients[client_end].packets_sent += 1
				clients[client_end].bytes_sent += uint(bytes_sent)
			}
		}
	}
}
