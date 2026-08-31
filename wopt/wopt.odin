package wopt

import "core:strings"
import "core:fmt"
import "core:container/xar"

import B "../base"

// Types

Type_Id :: distinct u32

// NOTE: No integer type is signed or unsigned, operations define signedness, not type
Builtin_Type :: enum {
	I32,
}

Type_Kind :: enum {
	Builtin,
}

Type :: struct {
	kind:  Type_Kind,
	id:    Type_Id,
	name:  string, // for debug purposes
	size:  int,
	align: int,
}

builtin_type_types := [Builtin_Type]Type{
	.I32 = { name = "i32", size = 4, align = 4 },
}

type_add :: proc(m: ^Module, type: Type) -> (id: Type_Id) {
	id           = Type_Id(xar.len(m.types))
	type_ptr, _ := xar.append_and_get_ptr(&m.types, type)
	type_ptr.id  = id

	type_ptr.name, _ = strings.intern_get(&m.interner, type.name)
	return
}

type_get_builtin :: proc(m: ^Module, builtin: Builtin_Type) -> (id: Type_Id) {
	return m.bultin_types[builtin]
}

// Functions

Function_Id :: distinct u32

Function :: struct {
	id:         Function_Id,
	name:       string,
	parameters: []Type_Id,
	result:     Type_Id,
}

function_add :: proc(m: ^Module, function: Function) -> (id: Function_Id) {
	id               = Function_Id(xar.len(m.functions))
	function_ptr, _ := xar.append_and_get_ptr(&m.functions, function)
	function_ptr.id  = id

	function_ptr.name, _ = strings.intern_get(&m.interner, function.name)
	return
}

// Module

Module :: struct {
	arena:    ^B.Arena,
	interner: strings.Intern,

	// Types
	types:        xar.Array(Type, 4),
	bultin_types: [Builtin_Type]Type_Id,

	// Functions
	functions: xar.Array(Function, 4),
}

module_new :: proc() -> (m: ^Module) {
	m = B.arena_bootstrap_new(Module, "arena")

	for type in Builtin_Type {
		m.bultin_types[type] = type_add(m, builtin_type_types[type])
	}

	return
}

module_free :: proc(m: ^Module) {
	strings.intern_destroy(&m.interner)
	B.arena_destroy(m.arena)
}

main :: proc() {
	m := module_new()
	defer module_free(m)

	function_add(m, Function { name = "main" })

	fmt.println("Types:")
	for it := xar.iterator(&m.types); type in xar.iterate_by_val(&it) {
		fmt.printfln("  %q: Kind = %v, Id = %v, size = %x, align = %x", type.name, type.kind, type.id, type.size, type.align)
	}
	fmt.println("Functions:")
	for it := xar.iterator(&m.functions); function in xar.iterate_by_val(&it) {
		fmt.printfln("  %q: Id = %v, params = %v, result = %v", function.name, function.id, function.parameters, function.result)
	}
}
