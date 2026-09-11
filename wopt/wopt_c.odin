package wopt

import "base:runtime"

@export
wopt_module_new :: proc "c" () -> ^Module {
	context = runtime.default_context()
	return module_new()
}

@export
wopt_module_free :: proc "c" (m: ^Module) {
	context = runtime.default_context()
	module_free(m)
}

@export
wopt_type_none :: proc "c"(m: ^Module) -> Type_Id {
	context = runtime.default_context()
	return type_none(m)
}

@export
wopt_type_i32 :: proc "c"(m: ^Module) -> Type_Id {
	context = runtime.default_context()
	return type_i32(m)
}

@export
wopt_type_mem :: proc "c"(m: ^Module) -> Type_Id {
	context = runtime.default_context()
	return type_mem(m)
}

@export
wopt_type_struct_simple :: proc "c"(m: ^Module, members: [^]Type_Id, member_count: int) -> Type_Id {
	context = runtime.default_context()
	return type_struct_simple(m, ..members[:member_count])
}

@export
wopt_type_struct :: proc "c"(
	m:            ^Module,
	size, align:  int,
	members:      [^]Type_Member,
	member_count: int,
) -> Type_Id {
	context = runtime.default_context()
	return type_struct(m, size, align, ..members[:member_count])
}

@export
wopt_function_add :: proc "c"(
	m:               ^Module,
	name:            string,
	result_type:     Type_Id,
	parameters:      [^]Type_Id,
	parameter_count: int,
	flags_bits:      u32,
) -> Function_Id {
	context = runtime.default_context()

	return function_add(
		m,
		name,
		result_type,
		..parameters[:parameter_count],
		flags = transmute(Function_Flags)flags_bits,
	)
}

@export
wopt_module_freeze_for_build :: proc "c"(m: ^Module) {
	context = runtime.default_context()
	module_freeze_for_build(m)
}

@export
wopt_module_is_frozen :: proc "c"(m: ^Module) -> u8 {
	context = runtime.default_context()
	return u8(module_is_frozen(m))
}

@export
wopt_thread_build_context_new :: proc "c"(
	m:              ^Module,
	error_callback: SSA_Verify_Error_Callback,
	user_data:      rawptr,
) -> ^Thread_Build_Context {
	context = runtime.default_context()
	return thread_build_context_new(m, error_callback, user_data)
}

@export
wopt_thread_build_context_free :: proc "c"(tbctx: ^Thread_Build_Context) {
	context = runtime.default_context()
	thread_build_context_free(tbctx)
}

@export
wopt_build_function_begin :: proc "c"(tbctx: ^Thread_Build_Context, function_id: Function_Id) {
	context = runtime.default_context()
	build_function_begin(tbctx, function_id)
}

@export
wopt_build_function_end :: proc "c"(tbctx: ^Thread_Build_Context) -> int {
	context = runtime.default_context()
	return build_function_end(tbctx)
}

@export
wopt_build_begin_block :: proc "c"(tbctx: ^Thread_Build_Context, kind: u32) -> Block_Id {
	context = runtime.default_context()
	assert(kind <= u32(Block_Kind.Exit))
	return build_begin_block(tbctx, Block_Kind(kind))
}

@export
wopt_build_end_block :: proc "c"(tbctx: ^Thread_Build_Context) {
	context = runtime.default_context()
	build_end_block(tbctx)
}

@export
wopt_build_block_set_control_value :: proc "c"(tbctx: ^Thread_Build_Context, value_id: Value_Id) {
	context = runtime.default_context()
	build_block_set_control_value(tbctx, value_id)
}

@export
wopt_build_set_start_block :: proc "c"(tbctx: ^Thread_Build_Context, block_id: Block_Id) {
	context = runtime.default_context()
	build_set_start_block(tbctx, block_id)
}

@export
wopt_build_value_get_argument :: proc "c"(tbctx: ^Thread_Build_Context, parameter_index: int) -> Value_Id {
	context = runtime.default_context()
	return build_value_get_argument(tbctx, parameter_index)
}

@export
wopt_build_value_argument :: proc "c"(tbctx: ^Thread_Build_Context, parameter_index: u32) -> Value_Id {
	context = runtime.default_context()
	return build_value_argument(tbctx, parameter_index)
}

@export
wopt_build_value_init_memory :: proc "c"(tbctx: ^Thread_Build_Context) -> Value_Id {
	context = runtime.default_context()
	return build_value_init_memory(tbctx)
}

@export
wopt_build_value_const32 :: proc "c"(tbctx: ^Thread_Build_Context, value: u32) -> Value_Id {
	context = runtime.default_context()
	return build_value_const32(tbctx, value)
}

@export
wopt_build_value_return :: proc "c"(tbctx: ^Thread_Build_Context, value_id: Value_Id) -> Value_Id {
	context = runtime.default_context()
	return build_value_return(tbctx, value_id)
}

@export
wopt_build_type_none :: proc "c"(tbctx: ^Thread_Build_Context) -> Type_Id {
	context = runtime.default_context()
	return build_type_none(tbctx)
}

@export
wopt_build_type_i32 :: proc "c"(tbctx: ^Thread_Build_Context) -> Type_Id {
	context = runtime.default_context()
	return build_type_i32(tbctx)
}

@export
wopt_build_type_mem :: proc "c"(tbctx: ^Thread_Build_Context) -> Type_Id {
	context = runtime.default_context()
	return build_type_mem(tbctx)
}

@export
wopt_build_type_struct_simple :: proc "c"(
	tbctx:        ^Thread_Build_Context,
	members:      [^]Type_Id,
	member_count: int,
) -> Type_Id {
	context = runtime.default_context()
	return build_type_struct_simple(tbctx, ..members[:member_count])
}

@export
wopt_build_type_struct :: proc "c"(
	tbctx:        ^Thread_Build_Context,
	size, align:  int,
	members:      [^]Type_Member,
	member_count: int,
) -> Type_Id {
	context = runtime.default_context()
	return build_type_struct(tbctx, size, align, ..members[:member_count])
}
