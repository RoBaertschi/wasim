#+vet explicit-allocators
package wopt

import "core:sync"
import "base:runtime"

import B "../base"

// Based on the principles from the string interner from the odin compiler: https://github.com/odin-lang/Odin/blob/master/src/string_interner.cpp

// TODO(robin): tune these
TYPE_INTERNER_CELL_SIZE :: 8
TYPE_INTERNER_MUTEX_STRIPE_SIZE :: 1 << 10 // 1024
TYPE_INTERNER_MUTEX_STRIPE_MASK :: TYPE_INTERNER_MUTEX_STRIPE_SIZE - 1
TYPE_INTERNER_THREAD_LOCAL_SIZE :: runtime.Megabyte * 2

TYPE_INTERNER_CELL_COUNT :: 1 << 17 // 2M
TYPE_INTERNER_CELL_MASK  :: TYPE_INTERNER_CELL_COUNT - 1

TYPE_INTERNER_CACHE_LINE_SIZE  :: 64 * 2

Type_Interner_Cell :: struct #align(TYPE_INTERNER_CACHE_LINE_SIZE) {
	offsets: [TYPE_INTERNER_CELL_SIZE]u32,
	hashes:  [TYPE_INTERNER_CELL_SIZE]u64,
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

type_interner_new :: proc() -> (i: ^Type_Interner) {
	i         = B.arena_bootstrap_new(Type_Interner, "arena", flags = {.No_Growing})
	i.cells   = B.arena_push_make(i.arena, []Type_Interner_Cell, TYPE_INTERNER_CELL_COUNT)
	i.mutexes = B.arena_push_make(i.arena, []Type_Interner_Padded_Mutex, TYPE_INTERNER_MUTEX_STRIPE_SIZE)

	return
}

type_interner_load :: proc(i: ^Type_Interner, id: Type_Id) -> (t: Type) {
	return
}
