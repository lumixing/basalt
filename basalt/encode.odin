package basalt

import "core:encoding/endian"

encode_varint_len :: proc(value: varint) -> (len: uint) {
	val := cast(u32)value

	for {
		byte_val := cast(u8)(val & 0x7F)
		val >>= 7
		
		if val != 0 {
			byte_val |= 0x80
		}
		
		len += 1
		
		if val == 0 {
			break
		}
	}

	return
}

encode_string :: proc(buffer: ^[dynamic]u8, value: string) {
	encode_varint(buffer, varint(len(value)))
	append(buffer, ..transmute([]u8)value)
}

encode_i64 :: proc(buffer: ^[dynamic]u8, value: i64) {
	temp_buf: [size_of(i64)]u8
	ok := endian.put_i64(temp_buf[:], .Big, value)
	assert(ok)
	append(buffer, ..temp_buf[:])
}

encode_varint :: proc(buffer: ^[dynamic]u8, value: varint) {
	val := cast(u32)value

	for {
		byte_val := cast(u8)(val & 0x7F)
		val >>= 7
		
		if val != 0 {
			byte_val |= 0x80
		}
		
		append(buffer, byte_val)
		
		if val == 0 {
			break
		}
	}
}
