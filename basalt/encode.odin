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

encode_bool :: proc(buffer: ^[dynamic]u8, value: bool) {
	append(buffer, value ? 0x01 : 0x00)
}

encode_u16 :: proc(buffer: ^[dynamic]u8, value: u16) {
	temp_buf: [size_of(u16)]u8
	ok := endian.put_u16(temp_buf[:], .Big, value)
	assert(ok)
	append(buffer, ..temp_buf[:])
}

encode_i32 :: proc(buffer: ^[dynamic]u8, value: i32) {
	temp_buf: [size_of(i32)]u8
	ok := endian.put_i32(temp_buf[:], .Big, value)
	assert(ok)
	append(buffer, ..temp_buf[:])
}

encode_i64 :: proc(buffer: ^[dynamic]u8, value: i64) {
	temp_buf: [size_of(i64)]u8
	ok := endian.put_i64(temp_buf[:], .Big, value)
	assert(ok)
	append(buffer, ..temp_buf[:])
}

encode_f32 :: proc(buffer: ^[dynamic]u8, value: f32) {
	temp_buf: [size_of(f32)]u8
	ok := endian.put_f32(temp_buf[:], .Big, value)
	assert(ok)
	append(buffer, ..temp_buf[:])
}

encode_f64 :: proc(buffer: ^[dynamic]u8, value: f64) {
	temp_buf: [size_of(f64)]u8
	ok := endian.put_f64(temp_buf[:], .Big, value)
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
