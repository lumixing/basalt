package basalt

import "core:encoding/endian"

encode_i64 :: proc(value: i64) -> (buffer: []u8) {
	buffer_dynamic := make([]u8, size_of(i64))

	ok := endian.put_i64(buffer_dynamic[:], .Big, value)
	assert(ok)

	buffer = buffer_dynamic[:]

	return
}

encode_string :: proc(value: string) -> (buffer: []u8) {
	buffer_dynamic: [dynamic]u8

	length := encode_varint(i32(len(value)))
	defer delete(length)
	append(&buffer_dynamic, ..length)

	append(&buffer_dynamic, ..transmute([]u8)value)

	buffer = buffer_dynamic[:]

	return
}

encode_varint :: proc(value: varint) -> (buffer: []u8) {
	buffer_dynamic: [dynamic]u8
	val := cast(u32)value

	for {
		byte_val := cast(u8)(val & 0x7F)
		val >>= 7
		
		if val != 0 {
			byte_val |= 0x80
		}
		
		append(&buffer_dynamic, byte_val)
		
		if val == 0 {
			break
		}
	}

	buffer = buffer_dynamic[:]

	return
}
