#+vet explicit-allocators
package wopt

import "core:fmt"

import B "../base"

SSA_Verify_Error_Callback :: #type proc "c"(
	tbctx:       ^Thread_Build_Context, // used to indentify which builder created the diagnostic, treat as read-only
	user_data:   rawptr,
	function_id: Function_Id,
	message:     string,
)

ssa_verify_function :: proc(tbctx: ^Thread_Build_Context, function_id: Function_Id) -> (errors: int) {
	module := tbctx.module
	function := function_get(module, function_id)

	for block in function.build_body.blocks {
		switch block.kind {
		case .Exit:
			if Value_Id(len(function.build_body.values)) <= block.control {
				errors += 1
				if tbctx.error_callback != nil {
					temp := B.TEMP_ALLOCATOR_GUARD()
					message := fmt.aprintf("invalid exit block control value %%v%v", block.control, allocator = temp)
					tbctx.error_callback(
						tbctx,
						tbctx.user_data,
						function_id,
						message
					)
				}
			} else {
				value := function.build_body.values[block.control]
				if value.type != build_type_mem(tbctx) {
					errors += 1
					if tbctx.error_callback != nil {
						temp := B.TEMP_ALLOCATOR_GUARD()
						message := fmt.aprintf("invalid type ", block.control, allocator = temp)
						tbctx.error_callback(
							tbctx,
							tbctx.user_data,
							function_id,
							message
						)
					}
				}
			}


		}
	}

	return
}
