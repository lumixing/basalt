package basalt

import "core:time"
import "core:fmt"
import "core:net"
import "core:thread"
import "core:encoding/json"
import "core:math/noise"

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

	thread.create_and_start_with_poly_data2(client_socket, client_end, proc(client_socket: net.TCP_Socket, client_end: ClientEndpoint) {
		fmt.println("starting beating")
		last_heartbeat := time.now()
		for bool(client_end in clients) {
			if clients[client_end].state == .Play {
				if time.duration_seconds(time.diff(time.now(), last_heartbeat)) > 5 {
					fmt.println("beat!")
					last_heartbeat = time.now()
					packet_send(client_socket, client_end, CBP_KeepAlive {
						id = 0,
					})
				}
			}
		}
		fmt.println("stopped beating")
	})

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
		case .Login:
			switch packet.id {
			case 0x00:
				sbp := sbp_decode(SBP_LoginStart, packet.data)
				append(&packets, ServerBoundPacket(sbp))

				packet_send(client_socket, client_end, CBP_LoginSuccess {
					uuid     = "c1724db6-9479-4aeb-90cb-00ab8a1d2a91",
					username = sbp.name,
				})

				clients[client_end].username = sbp.name
				clients[client_end].uuid = "c1724db6-9479-4aeb-90cb-00ab8a1d2a91"
				clients[client_end].state = .Play

				packet_send(client_socket, client_end, CBP_JoinGame {
					entity_id = 69,
					gamemode = 1,
					dimension = 0,
					difficulty = 3,
					max_players = 69,
					level_type = "default",
					reduced_debug_info = false,
				})

				packet_send(client_socket, client_end, CBP_PlayerPositionAndLook {
					x = 32,
					y = 128+16,
					z = 32,
					yaw = 0,
					pitch = 0,
					flags = 0,
				})

				for cx in 0..<4 {
					for cz in 0..<4 {
						chunk_data: [dynamic]u8
						defer delete(chunk_data)
		
						// block ids
						CHUNK_SECTIONS :: 8
						for i in 0..<4096*CHUNK_SECTIONS {
							type := 0
							metadata := 0
		
							// For i in 0..<16*16*16*16 (total chunk size)
							section := i / (16*16*16)           // Which 16-block section (0-15)
							block_in_section := i % (16*16*16)  // Block index within that section
		
							// Within the section, blocks are in Y,Z,X order
							section_y := block_in_section / (16*16)     // Y within section (0-15)  
							section_zx := block_in_section % (16*16)    // Remaining Z,X index
							z := section_zx / 16                        // Z coordinate (0-15)
							x := section_zx % 16                        // X coordinate (0-15)
		
							// Final world coordinates
							world_y := section * 16 + section_y         // Absolute Y (0-255)
							world_x := x                                // X within chunk (0-15)
							world_z := z                                // Z within chunk (0-15)

							world_x += cx*16
							world_z += cz*16
		
							v := noise.noise_3d_improve_xz(0, {f64(world_x), f64(world_y), f64(world_z)}/25)
							if v < 0 {
								type = 1
							}
		
							append(&chunk_data, u8((type << 4) | metadata))
							append(&chunk_data, u8(type >> 4))
						}
		
						encode_varint(&chunk_data, 8) // both arrays
						encode_varint(&chunk_data, 16*16*16*2) // Varint of both array's total elements 
		
						// block light
						for _ in 0..<2048*CHUNK_SECTIONS {
							append(&chunk_data, 0)
						}
		
						// sky light
						for _ in 0..<2048*CHUNK_SECTIONS {
							append(&chunk_data, 0xFF)
						}
		
						// biomes
						for _ in 0..<256 {
							append(&chunk_data, 1)
						}
		
						packet_send(client_socket, client_end, CBP_ChunkData {
							chunk_x = i32(cx),
							chunk_z = i32(cz),
							ground_up = true,
							primary_bitmask = 0x00FF,
							size = varint(len(chunk_data)),
							data = chunk_data[:],
						})
					}
				}

				packet_send(client_socket, client_end, CBP_ChatMessage {
					json_data = fmt.tprintf(`{{"text":"welcome, %s!!1"}}`, clients[client_end].username),
					position = 0,
				})
			}
		case .Play:
			switch packet.id {
			case 0x00:
				sbp := sbp_decode(SBP_KeepAlive, packet.data)
				append(&packets, ServerBoundPacket(sbp))

				// packet_send(client_socket, client_end, CBP_KeepAlive {
				// 	id = sbp.id,
				// })
			}
		}
	}
}

packet_send :: proc(client_socket: net.TCP_Socket, client_end: ClientEndpoint, cbp: ClientBoundPacket) {
	append(&packets, cbp)
				
	buf := packet_encode(cbp_encode(cbp))
	defer delete(buf)
	ldebug("sent", buf)

	bytes_sent, send_err := net.send_tcp(client_socket, buf[:])
	lassert(send_err == nil, "could not send data:", send_err)
	clients[client_end].packets_sent += 1
	clients[client_end].bytes_sent += uint(bytes_sent)
}
