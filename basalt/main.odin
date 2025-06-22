package basalt

import "core:fmt"
import "core:net"
import "core:thread"

RECV_BUFFER_SIZE :: 4096
VERSION          :: "1.8.9"
PACKET_PROTOCOL  :: 47

main :: proc() {
	log_init()
	defer log_free()

	defer clients_free()

	server_config := server_config_init()

	listen_socket, listen_err := net.listen_tcp({
		address = net.IP4_Loopback,
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
		clients[client_end] = {}		

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
	}
}
