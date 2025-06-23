package basalt

packets: [dynamic]BoundPacket

BoundPacket :: union #no_nil {
	ServerBoundPacket,
	ClientBoundPacket,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Packet_format
Packet :: struct {
	length: varint,
	id:     varint,
	data:   []u8,
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

packet_encode :: proc(packet: Packet) -> []u8 {
	buffer: [dynamic]u8

	encode_varint(&buffer, packet.length)
	encode_varint(&buffer, packet.id)
	append(&buffer, ..packet.data)

	delete(packet.data)

	return buffer[:]
}
