package basalt

import "core:reflect"

ClientBoundPacket :: union #no_nil {
	CBP_Response,
	CBP_Pong,
	CBP_LoginSuccess,
	CBP_JoinGame,
	CBP_ChunkData,
	CBP_PlayerPositionAndLook,
	CBP_ChatMessage,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Response
CBP_Response :: struct {
	json: string,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Ping
CBP_Pong :: struct {
	payload: i64,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Login_Success
CBP_LoginSuccess :: struct {
	uuid:     string,
	username: string,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Join_Game
CBP_JoinGame :: struct {
	entity_id:   i32,
	gamemode:    u8,
	dimension:   i8,
	difficulty:  u8,
	max_players: u8,
	level_type:  string,
	reduced_debug_info: bool,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Chunk_Data
CBP_ChunkData :: struct {
	chunk_x: i32,
	chunk_z: i32,
	ground_up: bool,
	primary_bitmask: u16,
	size: varint,
	data: []u8,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Player_Position_And_Look
CBP_PlayerPositionAndLook :: struct {
	x:     f64,
	y:     f64,
	z:     f64,
	yaw:   f32,
	pitch: f32,
	flags: i8,
}

// https://minecraft.wiki/w/Protocol?oldid=2772100#Chat_Message
CBP_ChatMessage :: struct {
	json_data: string,
	position:  i8,
}

cbp_id :: proc(cbp: ClientBoundPacket) -> varint {
	switch _ in cbp {
	case CBP_Response:     return 0x00
	case CBP_Pong:         return 0x01
	case CBP_LoginSuccess: return 0x02
	case CBP_JoinGame:     return 0x01
	case CBP_ChatMessage:  return 0x02
	case CBP_ChunkData:    return 0x21
	case CBP_PlayerPositionAndLook: return 0x08
	}

	unreachable()
}

cbp_encode :: proc(cbp: ClientBoundPacket) -> Packet {
	data: [dynamic]u8

	for field in reflect.struct_fields_zipped(reflect.union_variant_typeid(cbp)) {
		switch field.type.id {
		case string:
			encode_string(&data, reflect.struct_field_value(cbp, field).(string))
		case bool:
			encode_bool(&data, reflect.struct_field_value(cbp, field).(bool))
		case varint:
			encode_varint(&data, reflect.struct_field_value(cbp, field).(varint))
		case u8:
			append(&data, reflect.struct_field_value(cbp, field).(u8))
		case i8:
			append(&data, u8(reflect.struct_field_value(cbp, field).(i8)))
		case u16:
			encode_u16(&data, reflect.struct_field_value(cbp, field).(u16))
		case i32:
			encode_i32(&data, reflect.struct_field_value(cbp, field).(i32))
		case i64:
			encode_i64(&data, reflect.struct_field_value(cbp, field).(i64))
		case f32:
			encode_f32(&data, reflect.struct_field_value(cbp, field).(f32))
		case f64:
			encode_f64(&data, reflect.struct_field_value(cbp, field).(f64))
		case []u8:
			append(&data, ..reflect.struct_field_value(cbp, field).([]u8))
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
