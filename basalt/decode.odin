package basalt

import "core:encoding/endian"

DecodeError :: union #shared_nil {
	VarIntError,
	StringError,
	EndianError,
}

VarIntError :: enum {
	InvalidOffset,
	InvalidSize,
	Incomplete,
}

StringError :: enum {
	InvalidLength,
}

EndianError :: enum {
	InvalidEndian,
}


decode_check_offset :: proc(buffer: []u8, offset: uint) -> (err: DecodeError) {
	if offset >= uint(len(buffer)) {
		err = .InvalidOffset
	}

	return
}

decode_u16 :: proc(buffer: []u8, offset: ^uint) -> (value: u16, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	ok: bool
	value, ok = endian.get_u16(buffer[offset^:][:size_of(u16)], .Big)

	if !ok {
		err = .InvalidEndian
		return
	}

	offset^ += size_of(u16)

	return
}

decode_i64 :: proc(buffer: []u8, offset: ^uint) -> (value: i64, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	ok: bool
	value, ok = endian.get_i64(buffer[offset^:][:size_of(i64)], .Big)

	if !ok {
		err = .InvalidEndian
		return
	}

	offset^ += size_of(i64)

	return
}

decode_string :: proc(buffer: []u8, offset: ^uint) -> (value: string, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	length := decode_varint(buffer, offset) or_return

	// if offset^ + uint(length) > len(buffer) {
	// 	err = .InvalidSize
	// 	return
	// }

	value = string(buffer[offset^:][:length])
	offset^ += uint(length)

	return
}

decode_varint :: proc(buffer: []u8, offset: ^uint) -> (value: varint, err: DecodeError) {
	decode_check_offset(buffer, offset^) or_return

	offset_init := offset^
	position := 0
	value_raw: u32 = 0

	for i in offset_init..<uint(len(buffer)) {
		current_byte := buffer[i]
		offset^ += 1
		value_raw |= cast(u32)(current_byte & 0x7F) << cast(u32)(position * 7)

		if (current_byte & 0x80) == 0 {
			value = cast(i32)value_raw
			return
		}

		position += 1

		if position >= 5 {
			err = .InvalidSize
			return
		}
	}

	err = .Incomplete
	return
}
