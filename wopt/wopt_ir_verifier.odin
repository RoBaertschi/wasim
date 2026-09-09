#+vet explicit-allocators
package wopt

import "core:fmt"
import "core:mem"
import "core:strings"
import "base:runtime"

import B "../base"

SSA_Verify_Error_Callback :: #type proc "c"(
	tbctx:       ^Thread_Build_Context, // used to indentify which builder created the diagnostic, treat as read-only
	user_data:   rawptr,
	function_id: Function_Id,
	message:     string,
)

ssa_verify_error_callback_panic :: proc "c"(
	tbctx:       ^Thread_Build_Context,
	user_data:   rawptr,
	function_id: Function_Id,
	message:     string,
) {
	context = runtime.default_context()
	panic(message)
}

ssa_verify_function :: proc(tbctx: ^Thread_Build_Context, function_id: Function_Id) -> (errors: int) {
	module := tbctx.module
	function := function_get(module, function_id)

	error :: proc(tbctx: ^Thread_Build_Context, errors: ^int, function_id: Function_Id, message: string) {
		errors^ += 1
		if tbctx.error_callback != nil {
			tbctx.error_callback(tbctx, tbctx.user_data, function_id, message)
		}
	}

	errorf :: proc(tbctx: ^Thread_Build_Context, errors: ^int, function_id: Function_Id, format: string, args: ..any) {
		temp := B.TEMP_ALLOCATOR_GUARD()
		message := fmt.aprintf(format, ..args, allocator = temp)
		error(tbctx, errors, function_id, message)
	}

	is_value_id_valid :: proc(function_body: Function_Body, value_id: Value_Id) -> bool {
		assert(len(function_body.values) <= (1 << (size_of(Value_Id) * 8)) - 1)
		return value_id < Value_Id(len(function_body.values))
	}

	is_block_id_valid :: proc(function_body: Function_Body, block_id: Block_Id) -> bool {
		assert(len(function_body.blocks) <= (1 << (size_of(Value_Id) * 8)) - 1)
		return block_id < Block_Id(len(function_body.blocks))
	}

	error_builder :: proc(module: ^Module, allocator: mem.Allocator) -> (b: ^strings.Builder, p: ^SSA_Printer) {
		b = new(strings.Builder, allocator = allocator)
		strings.builder_init_none(b, allocator)
		p = new_clone(SSA_Printer { module = module, writer = strings.to_writer(b) }, allocator = allocator)

		return
	}

	type_string :: proc(module: ^Module, type_id: Type_Id, allocator: mem.Allocator) -> string {
		b := strings.builder_make_none(allocator)
		p := SSA_Printer { module = module, writer = strings.to_stream(&b) }
		ssa_write_type(&p, type_id)
		return strings.to_string(b)
	}

	value_id_string :: proc(module: ^Module, value_id: Value_Id, allocator: mem.Allocator) -> string {
		b := strings.builder_make_none(allocator)
		p := SSA_Printer { module = module, writer = strings.to_stream(&b) }
		ssa_write_value_id(&p, value_id)
		return strings.to_string(b)
	}

	block_id_string :: proc(module: ^Module, block_id: Block_Id, allocator: mem.Allocator) -> string {
		b := strings.builder_make_none(allocator)
		p := SSA_Printer { module = module, writer = strings.to_stream(&b) }
		ssa_write_block_id(&p, block_id)
		return strings.to_string(b)
	}

	if !is_block_id_valid(function.build_body, function.build_body.start) {
		temp := B.TEMP_ALLOCATOR_GUARD()
		errorf(
			tbctx,
			&errors,
			function_id,
			"",
		)
	}

	for block in function.build_body.blocks[1:] {
		switch block.kind {
		case .Exit:
			if !is_value_id_valid(function.build_body, block.control) {
				temp := B.TEMP_ALLOCATOR_GUARD()
				errorf(tbctx, &errors, function_id, "invalid exit block control value %v", value_id_string(module, block.control, temp))
			} else {
				value := function.build_body.values[block.control]
				if value.type != build_type_mem(tbctx) {
					temp := B.TEMP_ALLOCATOR_GUARD()
					errorf(
						tbctx,
						&errors,
						function_id,
						"invalid control value type %v for exit block, %v required instead",
						type_string(module, value.type, temp),
						type_string(module, build_type_mem(tbctx), temp),
					)
				}
			}

			for value_id in block.values {
				if !is_value_id_valid(function.build_body, value_id) {
					temp := B.TEMP_ALLOCATOR_GUARD()
					errorf(
						tbctx,
						&errors,
						function_id,
						"invalid value(%v) in block %v",
						value_id_string(module, value_id, temp),
						block_id_string(module, block.id, temp),
					)
					continue
				}

				value := function.build_body.values[value_id]
				switch value.operator {
				case .Argument:
					param_index := int(value.immediate)
					if len(function.parameters) <= param_index {
						temp := B.TEMP_ALLOCATOR_GUARD()
						errorf(
							tbctx,
							&errors,
							function_id,
							"parameter index(%v) in argumet value %v is wrong",
							param_index,
							value_id_string(module, value_id, temp)
						)
					} else {
						parameter_type := function.parameters[param_index]
						if parameter_type != value.type {
							temp := B.TEMP_ALLOCATOR_GUARD()
							errorf(
								tbctx,
								&errors,
								function_id,
								"type in argument value %v is not the same as the parameter: %v != %v",
								value_id_string(module, value_id, temp),
								type_string(module, value.type, temp),
								type_string(module, parameter_type, temp),
							)
						}
					}
				case .Init_Memory:
				case .Const32:
				case .Return:
					if !is_value_id_valid(function.build_body, value.arguments[0]) {
						temp := B.TEMP_ALLOCATOR_GUARD()
						errorf(
							tbctx,
							&errors,
							function_id,
							"first argument value(%v) in return %v value is invalid",
							value_id_string(module, value.arguments[0], temp),
							value_id_string(module, value_id, temp),
						)
					} else {
						return_value := function.build_body.values[value.arguments[0]]
						if return_value.type != function.result {
							temp := B.TEMP_ALLOCATOR_GUARD()
							errorf(
								tbctx,
								&errors,
								function_id,
								"first argument value (%v) in return %v value is wrong type: %v != %v",
								value_id_string(module, value.arguments[0], temp),
								value_id_string(module, value_id, temp),
								type_string(module, return_value.type, temp),
								type_string(module, function.result, temp),
							)
						}
					}
				}
			}
		}
	}

	return
}
