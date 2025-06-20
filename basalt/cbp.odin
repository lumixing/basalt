package basalt

// CBP: server -> client
ClientBoundPacket :: union { // add #no_nil
	CBP_Response,
	CBP_Pong,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Response
CBP_Response :: struct {
	json: string,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Ping
CBP_Pong :: struct {
	payload: i64,
}

cbp_encode :: proc(cbp: ClientBoundPacket) -> (buffer: []u8) {
	buffer_dynamic: [dynamic]u8

	switch p in cbp {
	case CBP_Response:
		append(&buffer_dynamic, 0x00)
		str := encode_string(p.json)
		defer delete(str)
		append(&buffer_dynamic, ..str)
	case CBP_Pong:
		append(&buffer_dynamic, 0x01)
		payload := encode_i64(p.payload)
		defer delete(payload)
		append(&buffer_dynamic, ..payload)
	}

	buffer_length := encode_varint(i32(len(buffer_dynamic)))
	defer delete(buffer_length)
	#reverse for pl in buffer_length {
		inject_at_elem(&buffer_dynamic, 0, pl)
	}

	buffer = buffer_dynamic[:]

	return
}
