#+vet explicit-allocators
package wopt

import "core:mem"
import "core:os"
import "core:strings"
import "core:fmt"
import "core:container/xar"

import B "../base"

// Functions

Function_Id :: distinct u32

FUNCTION_NONE :: Function_Id(0)

Function_Flag :: enum {
	Always_Inline = 0,
	Never_Inline,
	// Internal flags
	_In_Progress = 16, // TODO(robin): make this an extra state enum?
	_Build_Done,
}

Function_Flags :: bit_set[Function_Flag; u32]

Function_Body :: struct {
	blocks: []Block,
	values: []Value,
	start:  Block_Id,
}

Function :: struct {
	id:         Function_Id,
	abi:        ABI_Id,
	name:       string,
	flags:      Function_Flags,
	parameters: []Type_Id,
	result:     Type_Id,

	// TODO(robin): Improve comment
	// NOTE(robin): When the module is frozen and .Never_Inline in flags then this can never change again. A copy has to be made instead
	//              This is so that inlining can use an IR representation of this function without building a
	//              compile time dependency tree on the functions, which would make threading less effective
	//              this is a tradeoff made with performance, simplicity and optimization in optimization in mind
	//              while it does make inlining a bit worse (we inline an unoptimized function, which could increase the inline
	//              cost for useless code), we gain faster compile times by not having dependencies on other functions at compile
	//              time, also it allows for a much simpler threading model
	//              we will probably introduce a hard max inline cost size, which would allow us to optimize large functions
	//              to not have to copy all of it
	build_body:   Function_Body,
	compile_body: Function_Body,
}

// Add a new function declaration to the module `m`.
//
// Parameters:
//  m           - the module to add the function to
//  name        - name of the function, used for abi and linking
//  result_type - return type of the function
//  parameters  - the type of parameters the function takes in
//  flags       - optional flags changing optimization/code generation behaviour
//
// Returns:
//  id - an id that represents the function inside the specific module
function_add :: proc(m: ^Module, name: string, result_type: Type_Id, parameter: ..Type_Id, flags := Function_Flags{}, abi_id := ABI_NONE) -> (id: Function_Id) {
	if m.frozen {
		panic("`function_add` is only available for unfrozen modules due to the builder api being multi threaded")
	}

	assert(!(.Never_Inline in flags && .Always_Inline in flags), "Always_Inline and Never_Inline cannot both be specified on the same function")
	function := Function {
		abi        = abi_id,
		name       = name,
		flags      = flags,
		result     = result_type,
		parameters = parameter,
	}

	if function.abi == ABI_NONE {
		function.abi = m.target.default_abi
	}

	id               = Function_Id(xar.len(m.functions))
	function_ptr, _ := xar.append_and_get_ptr(&m.functions, function)
	function_ptr.id  = id

	function_ptr.parameters = B.arena_push_make(m.arena, []Type_Id, len(function.parameters))
	copy(function_ptr.parameters, function.parameters)

	function_ptr.name, _ = strings.intern_get(&m.interner, function.name)
	return
}

function_get :: proc(m: ^Module, id: Function_Id) -> Function {
	return xar.get(&m.functions, id)
}

function_get_ptr :: proc(m: ^Module, id: Function_Id) -> ^Function {
	return xar.get_ptr(&m.functions, id)
}

// ABI

// NOTE: The ABI will be destroyed at module free, user_data should stay valid until then
// TODO(robin): Add destructor procedure?
abi_add :: proc(m: ^Module, user_data: rawptr, procedure: ABI_Procedure) -> (id: ABI_Id) {
	abi := ABI {
		user_data = user_data,
		procedure = procedure,
	}

	id = ABI_Id(xar.len(m.abis))
	abi_ptr, _ := xar.push_back_elem_and_get_ptr(&m.abis, abi)
	abi_ptr.id  = id

	return
}

_abi_get :: proc(m: ^Module, abi_id: ABI_Id) -> (abi: ABI) {
	return xar.get(&m.abis, abi_id)
}

// Module

Module :: struct {
	arena:    ^B.Arena,
	interner: strings.Intern,
	target:   Target,
	frozen:   bool,

	// Types
	type_interner:       ^Type_Interner,
	type_interner_arena: Type_Interner_Thread_Arena, // WARN: only vaild in !frozen

	// Functions
	functions: xar.Array(Function, 4),

	// ABI
	abis: xar.Array(ABI, 4),
	abi_amd64_sysv: ABI_Id,
}

module_new :: proc() -> (m: ^Module) {
	m = B.arena_bootstrap_new(Module, "arena")

	// NOTE: We use the heap allocator for the map, because storing a long lived map
	//       inside an arena wastes ~50%
	//       the strings themselves are ok to be stored in the arena
	strings.intern_init(&m.interner, B.arena_allocator(m.arena), os.heap_allocator())
	m.type_interner = type_interner_new()
	xar.init(&m.functions, B.arena_allocator(m.arena))
	xar.init(&m.abis, B.arena_allocator(m.arena))

	type_intern(m, { kind = .Memory })
	type_intern(m, { kind = .I32 })

	// add zero sentinal function
	xar.push_back(&m.functions, Function {})
	xar.push_back(&m.abis, ABI {})

	m.abi_amd64_sysv = abi_add(m, nil, amd64_abi_sysv)

	// TODO(robin, 20260912-120102): allow user to specify target
	m.target = target_infer(m)

	return
}

module_free :: proc(m: ^Module) {
	type_interner_free(m.type_interner)
	strings.intern_destroy(&m.interner)
	B.arena_destroy(m.arena)
}

module_freeze_for_build :: proc(m: ^Module) {
	m.frozen = true
}

module_is_frozen :: proc(m: ^Module) -> bool {
	return m.frozen
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintfln("=== %v allocations not freed: ===", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintfln("- %v bytes @ %v", entry.size, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	m := module_new()
  defer module_free(m)

  type_i32 := type_i32(m)

  func_id := function_add(m, "main", /* result */ type_i32, /* parameters */ type_i32, type_i32, flags = {})

  module_freeze_for_build(m)
  ensure(module_is_frozen(m))

  tbctx := thread_build_context_new(m)
  defer thread_build_context_free(tbctx)

  {
    build_function_begin(tbctx, func_id)

    block_id := build_begin_block(tbctx, .Exit)
    memory_value := build_value_init_memory(tbctx)
    const_value  := build_value_const32(tbctx, 69)
    _ = build_value_return(tbctx, const_value)

    build_block_set_control_value(tbctx, memory_value)
    build_end_block(tbctx)

    build_set_start_block(tbctx, block_id)

    build_function_end(tbctx)
  }

  p := SSA_Printer {
  	writer = os.to_writer(os.stdout),
   	module = m,
    options = {
    	indent = "\t",
    },
  }
  ssa_write_function_build_body(&p, func_id)

	// fmt.println("Types:")
	// for it := xar.iterator(&m.types); type in xar.iterate_by_val(&it) {
	// 	fmt.printfln("  - Kind = %v, Id = %v, size = %x, align = %x", type.kind, type.id, type.size, type.align)
	// }
	// fmt.println("Functions:")
	// for it := xar.iterator(&m.functions); function in xar.iterate_by_val(&it) {
	// 	fmt.printfln("  %q: Id = %v, params = %v, result = %v", function.name, function.id, function.parameters, function.result)
	// }
}

import "core:testing"

@test
module_function_add_not_zero :: proc(t: ^testing.T) {
	m := module_new()
	defer module_free(m)

	testing.expect(t, function_add(m, "", type_i32(m)) != 0)
}
