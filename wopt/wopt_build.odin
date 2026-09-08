#+vet explicit-allocators
package wopt

import "core:sync"
import "core:mem"
import "core:container/xar"

import B "../base"

// this is per thread and is not safe to be shared across threads, each thread should have exactly one of them
Thread_Build_Context :: struct {
	module:          ^Module,
	allocator:       mem.Allocator,
	permanent_arena: ^B.Arena,
	user_data:       rawptr,
	error_callback:  SSA_Verify_Error_Callback, // gets called on invalid ssa

	type_interner_arena: Type_Interner_Thread_Arena,

	build_arena:         ^B.Arena,
	current_function_id: Function_Id,
	current_function:    ^Function,

	current_block_id: Block_Id,
	current_block:    ^Block,
	blocks:           xar.Array(Block, 4),
	block_values:     xar.Array(Value_Id, 4),
	block_ctrl_value: Value_Id,

	values:           xar.Array(Value, 4),
	start_block:      Block_Id,
}

thread_build_context_new :: proc(m: ^Module) -> (tbctx: ^Thread_Build_Context) {
	assert(m != nil)

	tbctx             = B.arena_bootstrap_new(Thread_Build_Context, "permanent_arena")
	tbctx.module      = m
	tbctx.build_arena = B.arena_alloc()
	tbctx.allocator   = B.arena_allocator(tbctx.build_arena)

	return
}

thread_build_context_free :: proc(tbctx: ^Thread_Build_Context) {
	B.arena_destroy(tbctx.build_arena)
	B.arena_destroy(tbctx.permanent_arena)
}

build_function_begin :: proc(tbctx: ^Thread_Build_Context, function_id: Function_Id, loc := #caller_location) {
	assert(tbctx.current_function_id == FUNCTION_NONE, "tbctx.current_function != FUNCTION_NONE, did you forget to call build_function_end?", loc = loc)

	function := function_get_ptr(tbctx.module, function_id)
	old_flags := sync.atomic_or_explicit(&function.flags, Function_Flags{ ._In_Progress }, .Acquire)
	assert(._In_Progress not_in old_flags, "function_id is marked as in progress, this is invalid API usage, only one thread can build a function at a time", loc = loc)
	assert(._Build_Done not_in old_flags, "function_id is marked as build, this is invalid API usage, a function can be build only one time")
	tbctx.current_function_id = function_id
	tbctx.current_function    = function

	xar.init(&tbctx.blocks, tbctx.allocator)
	xar.init(&tbctx.values, tbctx.allocator)

	tbctx.start_block = BLOCK_NONE

	// Zero values
	xar.push_back(&tbctx.blocks, Block{})
	xar.push_back(&tbctx.values, Value{})
}

build_function_end :: proc(tbctx: ^Thread_Build_Context) {
	function := tbctx.current_function

	build_body := &function.build_body
	build_body.blocks = B.xar_push_copy(tbctx.permanent_arena, &tbctx.blocks)
	build_body.values = B.xar_push_copy(tbctx.permanent_arena, &tbctx.values)
	build_body.start  = tbctx.start_block
	function.flags += {._Build_Done}
	sync.atomic_and_explicit(&function.flags, ~Function_Flags{._In_Progress}, .Release)

	tbctx.current_function_id = FUNCTION_NONE
	tbctx.current_function    = nil
	B.arena_clear(tbctx.build_arena)
}

// TODO(robin): build_block_begin?
build_begin_block :: proc(tbctx: ^Thread_Build_Context, kind: Block_Kind, loc := #caller_location) -> (block_id: Block_Id) {
	assert(tbctx.current_block_id == BLOCK_NONE, "tbctx.current_block != BLOCK_NONE, did you forget to call build_end_block?", loc = loc)

	block_id      = Block_Id(xar.len(tbctx.blocks))
	block_ptr, _ := xar.push_back_elem_and_get_ptr(&tbctx.blocks, Block{ kind = kind })
	block_ptr.id  = block_id

	xar.init(&tbctx.block_values, tbctx.allocator)

	tbctx.current_block    = block_ptr
	tbctx.current_block_id = block_id

	return
}

build_end_block :: proc(tbctx: ^Thread_Build_Context, loc := #caller_location) {
	assert(tbctx.current_block_id != BLOCK_NONE, "tbctx.current_block == BLOCK_NONE, did you forget to call build_begin_block?", loc = loc)

	block_ptr := xar.get_ptr(&tbctx.blocks, tbctx.current_block_id)
	block_ptr.control = tbctx.block_ctrl_value
	block_ptr.values  = B.xar_push_copy(tbctx.permanent_arena, &tbctx.block_values)

	tbctx.current_block    = nil
	tbctx.current_block_id = BLOCK_NONE
}

build_block_set_control_value :: proc(tbctx: ^Thread_Build_Context, value_id: Value_Id) {
	switch tbctx.current_block.kind {
	case .Exit:
		value := _build_value_get(tbctx, value_id)
		assert(value.type == build_type_mem(tbctx))
		tbctx.block_ctrl_value = value_id
	}
}

build_set_start_block :: proc(tbctx: ^Thread_Build_Context, block_id: Block_Id) {
	tbctx.start_block = block_id
}

_build_value :: proc(tbctx: ^Thread_Build_Context, value: Value) -> (value_id: Value_Id) {
	value_id      = Value_Id(xar.len(tbctx.values))
	value_ptr, _ := xar.push_back_elem_and_get_ptr(&tbctx.values, value)
	value_ptr.id  = value_id

	if tbctx.current_block_id != BLOCK_NONE {
		xar.push_back(&tbctx.block_values, value_id)
	}
	return
}

_build_value_get :: proc(tbctx: ^Thread_Build_Context, value_id: Value_Id) -> (value: Value) {
	return xar.get(&tbctx.values, value_id)
}

build_value_get_argument :: proc(tbctx: ^Thread_Build_Context, param_index: int, loc := #caller_location) -> Value_Id {
	assert(param_index < len(tbctx.current_function.parameters), "param_index >= len(tbctx.current_function.parameters), out of bounds function argument value", loc = loc)
	return Value_Id(param_index + 1)
}

build_value_argument :: proc(tbctx: ^Thread_Build_Context, parameter_index: u32) -> Value_Id {
	type := build_type_none(tbctx)

	if 0 <= parameter_index && parameter_index < u32(len(tbctx.current_function.parameters)) {
		type = tbctx.current_function.parameters[parameter_index]
	}

	return _build_value(tbctx, { operator = .Argument, type = type, immediate = u64(parameter_index) })
}

build_value_init_memory :: proc(tbctx: ^Thread_Build_Context) -> Value_Id {
	return _build_value(tbctx, { operator = .Init_Memory, type = build_type_mem(tbctx) })
}

build_value_const32 :: proc(tbctx: ^Thread_Build_Context, value: u32) -> Value_Id {
	return _build_value(tbctx, { operator = .Const32, type = build_type_i32(tbctx), immediate = u64(value) })
}

build_value_return :: proc(tbctx: ^Thread_Build_Context, value_id: Value_Id) -> Value_Id {
	args := B.arena_push_make(tbctx.permanent_arena, []Value_Id, 1)
	args[0] = value_id

	return _build_value(tbctx, { operator = .Return, type = build_type_none(tbctx), arguments = args })
}

build_type_none :: proc(tbctx: ^Thread_Build_Context) -> Type_Id {
	return type_interner_none(tbctx.module.type_interner, &tbctx.type_interner_arena)
}

build_type_i32 :: proc(tbctx: ^Thread_Build_Context) -> Type_Id {
	return type_interner_i32(tbctx.module.type_interner, &tbctx.type_interner_arena)
}

build_type_mem :: proc(tbctx: ^Thread_Build_Context) -> Type_Id {
	return type_interner_mem(tbctx.module.type_interner, &tbctx.type_interner_arena)
}

build_type_struct_simple :: proc(tbctx: ^Thread_Build_Context, members: ..Type_Id) -> Type_Id {
	return type_interner_struct_simple(tbctx.module.type_interner, &tbctx.type_interner_arena, ..members)
}

build_type_struct :: proc(tbctx: ^Thread_Build_Context, size, align: int, members: ..Type_Member) -> Type_Id {
	return type_interner_struct(tbctx.module.type_interner, &tbctx.type_interner_arena, size, align, ..members)
}

import "core:testing"

@test
tbctx_test_lifecycle :: proc(t: ^testing.T) {
	m := module_new()
	defer module_free(m)

	tbctx := thread_build_context_new(m)
	defer thread_build_context_free(tbctx)
}

@test
tbctx_test_basic_example :: proc(t: ^testing.T) {
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
}
