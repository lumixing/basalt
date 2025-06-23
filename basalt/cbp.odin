package basalt

import "core:reflect"

ClientBoundPacket :: union #no_nil {
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

cbp_id :: proc(cbp: ClientBoundPacket) -> varint {
	switch _ in cbp {
	case CBP_Response: return 0x00
	case CBP_Pong:     return 0x01
	}

	unreachable()
}

cbp_encode :: proc(cbp: ClientBoundPacket) -> Packet {
	data: [dynamic]u8

	for field in reflect.struct_fields_zipped(reflect.union_variant_typeid(cbp)) {
		switch field.type.id {
		case string:
			encode_string(&data, reflect.struct_field_value(cbp, field).(string))
		case i64:
			encode_i64(&data, reflect.struct_field_value(cbp, field).(i64))
		case:
			lerror("could not encode", field.type.id, "in", cbp)
		}
	}

	return Packet {
		length = varint(encode_varint_len(cbp_id(cbp)) + len(data)),
		id   = cbp_id(cbp),
		data = data[:],
	}
}
