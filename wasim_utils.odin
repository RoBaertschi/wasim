package wasim

import "base:intrinsics"

Rng1 :: struct($T: typeid) {
	start, end: T,
}

rng1_clamp_to_slice :: proc(rng: Rng1($T), s: $S/[]$E) -> (result: Rng1(T)) {
	result.start = clamp(rng.start, 0,            len(s))
	result.end   = clamp(rng.end,   result.start, len(s))
	return
}

rng1_slice :: proc(rng: Rng1($T), s: $S/[]$E) -> S {
	return s[rng.start:rng.end]
}

rng1 :: proc(start, end: $T) -> (result: Rng1(T)) {
	result.start = start
	result.end   = end
	return
}

List :: struct($T: typeid)
	where intrinsics.type_has_field(T, "next"),
	      intrinsics.type_field_type(T, "next") == ^T{
	first, last: ^T,
	count:       int,
}

list_push :: proc(list: ^List($T), node: ^T) {
	list.count += 1
	if intrinsics.unlikely(list.first == nil) {
		list.first = node
		list.last  = node
	} else {
		assert(list.last != nil)
		list.last.next = node
		list.last      = node
	}
}
