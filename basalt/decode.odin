package basalt

import "core:encoding/endian"

decode_check_offset :: proc(buffer: []u8, offset: uint) -> bool {
	return offset < uint(len(buffer))
}

decode_u16 :: proc(buffer: []u8, offset: ^uint) -> Maybe(u16) {
	if !decode_check_offset(buffer, offset^) {
		return nil
	}

	value, ok := endian.get_u16(buffer[offset^:][:size_of(u16)], .Big)
	if !ok {
		return nil
	}

	offset^ += size_of(u16)

	return value
}

decode_i64 :: proc(buffer: []u8, offset: ^uint) -> Maybe(i64) {
	if !decode_check_offset(buffer, offset^) {
		return nil
	}

	value, ok := endian.get_i64(buffer[offset^:][:size_of(i64)], .Big)
	if !ok {
		return nil
	}

	offset^ += size_of(i64)

	return value
}

decode_string :: proc(buffer: []u8, offset: ^uint) -> Maybe(string) {
	if !decode_check_offset(buffer, offset^) {
		return nil
	}

	length := decode_varint(buffer, offset).?
	// todo: do length check

	defer offset^ += uint(length)
	return string(buffer[offset^:][:length])
}

decode_varint :: proc(buffer: []u8, offset: ^uint) -> Maybe(varint) {
	if !decode_check_offset(buffer, offset^) {
		return nil
	}

	offset_init := offset^
	position := 0
	value_raw: u32 = 0

	for i in offset_init..<uint(len(buffer)) {
		current_byte := buffer[i]
		offset^ += 1
		value_raw |= cast(u32)(current_byte & 0x7F) << cast(u32)(position * 7)

		if (current_byte & 0x80) == 0 {
			return cast(varint)value_raw
		}

		position += 1

		if position >= 5 {
			return nil
		}
	}

	return nil
}
