package basalt

PacketRaw :: struct {
	length: varint,
	id:     varint,
	buffer: []u8,
}

varint :: i32

state := State.Handshake

State :: enum varint {
	Handshake = 0,
	Status    = 1, // https://minecraft.wiki/w/Protocol?oldid=2772100#Status
	Login     = 2, // https://minecraft.wiki/w/Protocol?oldid=2772100#Login
	Play      = 3,
}
