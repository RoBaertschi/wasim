package wasim_base

import "core:sync"
import "core:mem/virtual"
import "core:math/linalg"
import "core:container/xar"

arena_new :: proc(arena: ^virtual.Arena, $T: typeid, loc := #caller_location) -> ^T {
	value, _ := virtual.new(arena, T, loc = loc)
	return value
}

arena_new_clone :: proc(arena: ^virtual.Arena, value: $T, loc := #caller_location) -> ^T {
	clone, _ := virtual.new_clone(arena, value, loc = loc)
	return clone
}

arena_make :: proc(arena: ^virtual.Arena, $T: typeid/[]$E, #any_int len: int, loc := #caller_location) -> T {
	value, _ := virtual.make(arena, T, len, loc = loc)
	return value
}

arena_destroy_bootstrapped :: proc(arena: ^virtual.Arena) {
	// locking the arena before freeing it
	sync.lock(&arena.mutex)
	local       := arena^
	local.mutex  = {} // resetting the mutex, nobody except this function has the local copy of this mutex
	virtual.arena_destroy(&local)
}

array_cast :: linalg.array_cast

Corner :: enum {
	Left_Top,
	Left_Bottom,
	Right_Top,
	Right_Bottom,

	_00 = Left_Top,
	_01 = Left_Bottom,
	_10 = Right_Top,
	_11 = Right_Bottom,
}

corner_vec :: proc(corner: Corner, $T: typeid) -> [2]T {
	switch corner {
	case ._00: return { 0, 0 }
	case ._10: return { 1, 0 }
	case ._01: return { 0, 1 }
	case ._11: return { 1, 1 }
	case:
		fmt.panicf("unhandled corner: %v", corner)
	}
}

xar_chunk_cap :: #force_inline proc(array: ^xar.Array($T, $SHIFT), index_in_chunk: uint) -> uint {
	_, _, chunk_cap := xar._meta_get(SHIFT, index_in_chunk)
	return chunk_cap
}

// Slices

slice_map_into :: proc(from: $F/[]$FE, into: $I/[]$IE, mapper: proc(item: FE) -> IE) {
	count := min(len(from), len(into))
	#no_bounds_check for i in 0..<count {
		into[i] = mapper(from[i])
	}
}

// Ranges

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

rng1_slice_map_into :: proc(range: Rng1($T), from: $F/[]$FE, into: $I/[]$IE, mapper: proc(item: FE) -> IE) {
	slice_map_into(rng1_slice(range, from), rng1_slice(range, into), mapper)
}
