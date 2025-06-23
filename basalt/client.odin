package basalt

clients: map[ClientEndpoint]^Client

clients_free :: proc() {
	for client_end, client in clients {
		free(client)
	}
	delete(clients)
}

ClientEndpoint :: bit_field u64 {
	ip0:  u8 | 8,
	ip1:  u8 | 8,
	ip2:  u8 | 8,
	ip3:  u8 | 8,
	port: u16 | 16, 
}

Client :: struct {
	state: State,
	packets_recv: uint,
	bytes_recv: uint,
	packets_sent: uint,
	bytes_sent: uint,
}

varint :: i32

State :: enum varint {
	Handshake = 0,
	Status    = 1, // https://minecraft.wiki/w/Protocol?oldid=2772100#Status
	Login     = 2, // https://minecraft.wiki/w/Protocol?oldid=2772100#Login
	Play      = 3,
}
