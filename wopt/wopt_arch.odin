#+vet explicit-allocators
package wopt

Architecture :: enum {
	Amd64,
}

Target :: struct {
	architecture: Architecture,
	default_abi:  ABI_Id,
}

// Infers the target based on the target that the library was compiled for
target_infer :: proc(m: ^Module) -> (target: Target) {
	target.architecture = .Amd64           // TODO(robin, 20260912-105812): add support for more architectures
	target.default_abi  = m.abi_amd64_sysv // TODO(robin, 20260912-120319): detect default abi based on OS

	return
}

Register     :: distinct u8
Register_Set :: bit_set[0..=63; u64]

REGISTER_INVALID :: Register(0xFF)

Register_Constraint :: struct {
	allowed: Register_Set,
	pin:     u8,
}

Register_Information :: struct {
	inputs:   #soa[]Register_Constraint,
	outputs:  #soa[]Register_Constraint,
	clobbers: Register_Set,
}

Operator_Information :: struct {
	register_information: Register_Information,
}

@rodata
operator_information: [Operator]Operator_Information

arch_init :: proc() {
	amd64_init()
}
