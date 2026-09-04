#+vet explicit-allocators
package wopt

import "core:math/bits"
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
	types:   [TYPE_INTERNER_CELL_SIZE]Type_Id,
	hashes:  [TYPE_INTERNER_CELL_SIZE]Type_Hash,
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
	used: uint,
	data: []byte,
}

type_interner_thread_arena_alloc :: proc(i: ^Type_Interner, a: ^Type_Interner_Thread_Arena, size, align: int) -> (data: []byte) {
	assert(0 <= size)
	assert(0 <= align)

	// align
	base := uintptr(raw_data(a.data))
	// We align using the actual data pointer, to avoid weird situations where the data ptr is weirdly aligned
	aligned := mem.align_forward_uintptr(uintptr(a.used) + base, uintptr(align)) - base

	if uintptr(len(a.data)) < aligned + uintptr(size) { // out of space
		sync.lock(&i.mutex)
		a.data = B.arena_push_make(i.arena, []byte, max(TYPE_INTERNER_THREAD_LOCAL_SIZE, size), uint(mem.PAGE_SIZE))
		a.used = 0
		sync.unlock(&i.mutex)

		data = type_interner_thread_arena_alloc(i, a, size, align)
	} else { // enough space
		a.used = uint(aligned) + uint(size)
		data   = a.data[aligned:aligned+uintptr(size)]
	}

	return
}

type_interner_new :: proc() -> (i: ^Type_Interner) {
	i         = B.arena_bootstrap_new(Type_Interner, "arena", flags = {.No_Growing})
	i.cells   = B.arena_push_make(i.arena, []Type_Interner_Cell, TYPE_INTERNER_CELL_COUNT)
	i.mutexes = B.arena_push_make(i.arena, []Type_Interner_Padded_Mutex, TYPE_INTERNER_MUTEX_STRIPE_SIZE)

	return
}

type_interner_free :: proc(i: ^Type_Interner) {
	B.arena_destroy(i.arena)
}

Type_Hash :: distinct u64

type_hash_from_type_key :: proc(key: Type_Key) -> (id: Type_Hash) {
	key := key

	hash_state: xxhash.XXH3_state
	xxhash.XXH3_64_reset(&hash_state)

	bytes_from_ptr :: proc(value: ^$T) -> []byte {
		return ([^]byte)(value)[:size_of(T)]
	}

	xxhash.XXH3_64_update(&hash_state, {u8(key.kind)})
	xxhash.XXH3_64_update(&hash_state, bytes_from_ptr(&key.size))
	xxhash.XXH3_64_update(&hash_state, bytes_from_ptr(&key.align))
	xxhash.XXH3_64_update(&hash_state, slice.reinterpret([]u8, key.members))

	id = Type_Hash(xxhash.XXH3_64_digest(&hash_state))

	// 0 is never a valid hash
	if id == 0 {
		id = 1
	}
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

type_interner_intern :: proc(i: ^Type_Interner, arena: ^Type_Interner_Thread_Arena, key: Type_Key) -> (id: Type_Id) {
	// NOTE(robin): you could turn this into like ~5 helper functions, I am not sure if that is of any use
	//       it is definitly seen as a "clean" way to do it, but nobody would ever need those functions
	//       again, also all the comments are an experiment, if they are more annoying than usefull, **I** will delete them

	if key.kind == .None {
		return
	}

	hash := type_hash_from_type_key(key)

	// cell index
	cell_index := u64(hash & TYPE_INTERNER_CELL_MASK)
	cell       := &i.cells[cell_index]

	// find entry
	outer: for {
		next : ^Type_Interner_Cell = intrinsics.atomic_load_explicit(&cell.next, .Acquire)

		for index in 0..<len(cell.hashes) {
			if intrinsics.atomic_load_explicit(&cell.hashes[index], .Acquire) == hash {
				to_compare := type_interner_load(i, cell.types[index])

				if type_key_equal(key, to_compare.key) {
					id = cell.types[index]
					break outer
				}
			}
		}

		if next == nil {
			break
		}

		cell = next
	}

	if id != 0 { // entry found
		return
	}

	// no entry found

	// find mutex
	mutex_index := len(i.mutexes) & TYPE_INTERNER_MUTEX_STRIPE_MASK
	mutex       := &i.mutexes[mutex_index]

	// lock stripe
	sync.guard(mutex)

	// check for insert after mutex lock (somebody else might have locked and added the entry already)
	load_cell: ^Type_Interner_Cell
	outer_check: for cell != nil {
		for index in 0..<len(cell.hashes) {
			if cell.hashes[index] == hash {
				to_compare := type_interner_load(i, cell.types[index])

				if type_key_equal(key, to_compare.key) {
					id = cell.types[index]
					break outer_check
				}
			}
		}
		load_cell = cell
		cell      = cell.next
	}

	// return if already there
	if id != 0 {
		return
	}

	// create and allocate type/type_ptr
	type      := type_create(key)
	type_data := type_interner_thread_arena_alloc(i, arena, size_of(Type), align_of(Type))
	type_ptr  := cast(^Type)raw_data(type_data)
	type_ptr^  = type

	// allocate members for newly allocate type
	members_data: []byte
	members_data = type_interner_thread_arena_alloc(i, arena, size_of(Type_Member) * len(type.members), align_of(Type_Member))

	// copy members from param into our own memory
	type_ptr.members = slice.reinterpret([]Type_Member, members_data)
	copy(type_ptr.members, type.members)

	// some sanity checks
	assert(len(type_ptr.members) == len(type.members))
	assert((uintptr(type_ptr) & (uintptr(TYPE_INTERNER_TYPE_ID_COMPRESS_SHIFT) - 1)) == 0)

	// get the type id
	type_ptr_compressed := (uintptr(type_ptr) - i.arena.data) >> TYPE_INTERNER_TYPE_ID_COMPRESS_SHIFT
	ensure(type_ptr_compressed <= bits.U32_MAX) // just to be sure
	id = Type_Id(type_ptr_compressed)

	// set the type id
	type.id = id

	// find and set next free cell
	for index in 0..<len(load_cell.hashes) {
		if load_cell.hashes[index] == 0 {
			load_cell.types[index] = id
			intrinsics.atomic_store_explicit(&load_cell.hashes[index], hash, .Release)
			return // WARN: Early return
		}
	}

	// allocate and insert new cell
	new_cell_data: []byte
	new_cell_data = type_interner_thread_arena_alloc(i, arena, size_of(Type_Interner_Cell), align_of(Type_Interner_Cell))

	new_cell := cast(^Type_Interner_Cell)raw_data(new_cell_data)
	new_cell.types[0]  = id
	new_cell.hashes[0] = hash

	intrinsics.atomic_store_explicit(&load_cell.next, new_cell, .Release)

	return
}

type_interner_get :: proc(i: ^Type_Interner, arena: ^Type_Interner_Thread_Arena, key: Type_Key) -> (t: Type) {
	id := type_interner_intern(i, arena, key)
	t   = type_interner_load(i, id)
	return
}

// Tests

import "core:testing"

@test
type_interner_intern_test :: proc(t: ^testing.T) {
	m := module_new()
	defer module_free(m)

	i := type_interner_new()
	defer type_interner_free(i)
	temp := B.TEMP_ALLOCATOR_GUARD()

	arena: Type_Interner_Thread_Arena

	id  := type_interner_intern(i, &arena, type_key_make(temp, .Results, {type = type_get_builtin(m, .I32)}))
	id2 := type_interner_intern(i, &arena, type_key_make(temp, .Results, {type = type_get_builtin(m, .I32)}))
	testing.expect_value(t, id2, id)
	id3 := type_interner_intern(i, &arena, type_key_make(temp, .Results, {type = type_get_builtin(m, .I32)}, {type = type_get_builtin(m, .I32)}))
	testing.expect(t, id3 != id)
}
