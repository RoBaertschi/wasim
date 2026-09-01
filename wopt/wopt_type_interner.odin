#+vet explicit-allocators
package wopt

import "base:runtime"
import "base:intrinsics"

import "core:mem"
import "core:sync"
import "core:slice"
import "core:hash/xxhash"

import B "../base"

// Based on the principles from the string interner from the odin compiler: https://github.com/odin-lang/Odin/blob/master/src/string_interner.cpp

// TODO(robin): tune these
// TODO(robin): make these configurable by the api user
TYPE_INTERNER_CELL_SIZE :: 8
TYPE_INTERNER_MUTEX_STRIPE_SIZE :: 1 << 10 // 1024
TYPE_INTERNER_MUTEX_STRIPE_MASK :: TYPE_INTERNER_MUTEX_STRIPE_SIZE - 1
TYPE_INTERNER_THREAD_LOCAL_SIZE :: runtime.Megabyte * 2

TYPE_INTERNER_CELL_COUNT :: 1 << 17 // 2M
TYPE_INTERNER_CELL_MASK  :: TYPE_INTERNER_CELL_COUNT - 1

TYPE_INTERNER_CACHE_LINE_SIZE  :: 64 * 2

TYPE_INTERNER_TYPE_ID_COMPRESS_SHIFT :: uint(intrinsics.constant_log2(align_of(Type)))

// NOTE(robin): we currently still use the same cell design from odin's string interner,
//              if this is actually worth it has to be measured
Type_Interner_Cell :: struct #align(TYPE_INTERNER_CACHE_LINE_SIZE) {
	types:   [TYPE_INTERNER_CELL_SIZE]Type,
	hashes:  [TYPE_INTERNER_CELL_SIZE]Type_Id,
	next:    ^Type_Interner_Cell,
}

Type_Interner_Padded_Mutex :: struct #align(TYPE_INTERNER_CACHE_LINE_SIZE) {
	using m: sync.Mutex,
}

Type_Interner :: struct {
	cells:   []Type_Interner_Cell,
	mutexes: []Type_Interner_Padded_Mutex,
	arena:   ^B.Arena,
	mutex:   Type_Interner_Padded_Mutex,
}

Type_Interner_Thread_Arena :: struct {
	base: uint,
	used: uint,
	data: []byte,
}

type_interner_thread_arena_alloc :: proc(a: ^Type_Interner_Thread_Arena, size, align: int) -> (data: []byte, err: runtime.Allocator_Error) {
	assert(0 <= size)
	assert(0 <= align)

	aligned := mem.align_forward_uint(a.used + a.base, uint(align)) - a.base

	if len(a.data) < aligned + uint(size) {
		err = .Out_Of_Memory
	} else {
		a.used = aligned + uint(size)
		data   = a.data[aligned:aligned+uint(size)]
	}

	return
}

type_interner_new :: proc() -> (i: ^Type_Interner) {
	i         = B.arena_bootstrap_new(Type_Interner, "arena", flags = {.No_Growing})
	i.cells   = B.arena_push_make(i.arena, []Type_Interner_Cell, TYPE_INTERNER_CELL_COUNT)
	i.mutexes = B.arena_push_make(i.arena, []Type_Interner_Padded_Mutex, TYPE_INTERNER_MUTEX_STRIPE_SIZE)

	return
}

Type_Hash :: distinct u64

type_id_from_type_key :: proc(key: Type_Key) -> (id: Type_Hash) {
	hash_state: xxhash.XXH3_state
	xxhash.XXH3_64_reset(&hash_state)

	xxhash.XXH3_64_update(&hash_state, {u8(key.kind)})
	xxhash.XXH3_64_update(&hash_state, slice.reinterpret([]u8, key.members))

	id = Type_Hash(xxhash.XXH3_64_digest(&hash_state))
	return
}

type_interner_load :: proc(i: ^Type_Interner, id: Type_Id) -> (t: Type) {
	if id == 0 {
		return
	}

	address := uintptr(uint(id) << TYPE_INTERNER_TYPE_ID_COMPRESS_SHIFT) + i.arena.data

	t = (^Type)(address)^

	return
}

@(disabled=true)
type_interner_api_design :: proc() {
	when false {
		global_type_interner := type_interner_new()
		defer type_interner_free()

		type_id := type_interner_intern(type, members)
		type    := type_interner_load(type)
	}
}
