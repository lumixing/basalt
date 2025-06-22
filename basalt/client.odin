package basalt

clients: map[ClientEndpoint]Client

clients_free :: proc() {
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

}
