package basalt

// CBP: server -> client
ClientBoundPacket :: union { // add #no_nil
	CBP_Response,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Response
CBP_Response :: struct {
	json: string,
}

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
