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

amd64_abi_sysv : ABI_Procedure : proc "c" (user_data: rawptr, parameters: []ABI_Value, result: ABI_Value) -> (caller_saved, callee_saved: Register_Set) {
	callee_saved = transmute(Register_Set)Amd64_Register_Set{ .RBX, .RSP, .RBP, .R12, .R13, .R14, .R15 }
	caller_saved = transmute(Register_Set)Amd64_Register_Set{}

	return
}
