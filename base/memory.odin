package wasim_base

bytes_from_ptr :: proc(ptr: ^$T) -> []byte {
	return ([^]u8)(ptr)[:size_of(T)]
}
