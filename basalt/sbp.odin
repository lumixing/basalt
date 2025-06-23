package basalt

import "core:reflect"
import "core:mem"
import intr "base:intrinsics"

ServerBoundPacket :: union #no_nil {
	SBP_Handshake,
	SBP_Request,
	SBP_Ping,
	SBP_LoginStart,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Handshake
SBP_Handshake :: struct {
	protocon_version: varint,
	server_address:   string,
	server_port:      u16,
	next_state:       State,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Request
SBP_Request :: struct {}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Ping
SBP_Ping :: struct {
	payload: i64,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Login_Start
SBP_LoginStart :: struct {
	name: string,
}

sbp_decode :: proc($T: typeid, data: []u8) -> T
	where intr.type_is_variant_of(ServerBoundPacket, T) {
	sbp: T
	offset: uint = 0

	for field in reflect.struct_fields_zipped(T) {
		switch field.type.id {
		case varint:
			value := decode_varint(data, &offset).?
			mem.copy(rawptr(uintptr(&sbp) + field.offset), &value, size_of(value))
		case State:
			value := decode_varint(data, &offset).?
			mem.copy(rawptr(uintptr(&sbp) + field.offset), &value, size_of(value))
		case string:
			value := decode_string(data, &offset).?
			mem.copy(rawptr(uintptr(&sbp) + field.offset), &value, size_of(value))
		case u16:
			value := decode_u16(data, &offset).?
			mem.copy(rawptr(uintptr(&sbp) + field.offset), &value, size_of(value))
		case i64:
			value := decode_i64(data, &offset).?
			mem.copy(rawptr(uintptr(&sbp) + field.offset), &value, size_of(value))
		case:
			lerror("could not decode", field.type.id, "in", typeid_of(T))
		}
	}

	return sbp
}
