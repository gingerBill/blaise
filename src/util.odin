package main

import "core:encoding/endian"

put_i32 :: #force_inline proc(b: []byte, v: i32) {
	endian.put_i32(b, .Little, v)
}

padding :: proc(num, pad: int) -> int {
	if num%pad == 0 {
		return 0
	}
	return pad - num%pad
}
