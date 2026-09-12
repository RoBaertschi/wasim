#+vet explicit-allocators
package wopt

Amd64_Register :: enum u8 {
	// GPR
	RAX,
	RCX,
	RDX,
	RBX,
	RSP,
	RBP,
	RSI,
	RDI,
	R8,
	R9,
	R10,
	R11,
	R12,
	R13,
	R14,
	R15,

	// XMM
	XMM0,
	XMM1,
	XMM2,
	XMM3,
	XMM4,
	XMM5,
	XMM6,
	XMM7,
	XMM8,
	XMM9,
	XMM10,
	XMM11,
	XMM12,
	XMM13,
	XMM14,
	XMM15,
}

Amd64_Register_Set :: bit_set[Amd64_Register; u64]

amd64_init :: proc() {}

amd64_abi_sysv : ABI_Procedure : proc "c" (user_data: rawptr, parameters: []ABI_Value, result: ABI_Value) -> (config: ABI_Config) {
	config.callee_saved = transmute(Register_Set)Amd64_Register_Set{ .RBX, .RSP, .RBP, .R12, .R13, .R14, .R15 }
	config.caller_saved = transmute(Register_Set)Amd64_Register_Set{
		.RAX, .RDI, .RSI, .RCX, .RDX, .R8, .R9, .R10, .R11,

		// Float registers are all caller saved
		.XMM0,  .XMM1,  .XMM2,  .XMM3,  .XMM4,  .XMM5,  .XMM6,  .XMM7,
		.XMM8,  .XMM9,  .XMM10, .XMM11, .XMM12, .XMM13, .XMM14, .XMM15,
	}

	config.align_stack_to = 16

	argument_registers := [?]Amd64_Register{
		.RDI,
		.RSI,
		.RDX,
		.RCX,
		.R8,
		.R9,
	}

	current_argument_register := 0
	current_stack_offset := 0

	ensure_contextless(result.type.kind == .I32)

	result.location.register = transmute(Register)Amd64_Register.RAX

	parameters_in_registers := parameters[:min(len(parameters), len(argument_registers))]
	parameters_on_the_stack := parameters[len(parameters_in_registers):]

	for param in parameters_in_registers {
		ensure_contextless(param.type.kind == .I32)
		param.location.register    = transmute(Register)argument_registers[current_argument_register]
		current_argument_register += 1
	}

	for param in parameters_on_the_stack {
		ensure_contextless(param.type.kind == .I32)
		param.location.register  = REGISTER_INVALID
		param.location.offset    = current_stack_offset
		current_stack_offset    += 8
	}

	config.argument_stack_size = current_stack_offset

	return
}
