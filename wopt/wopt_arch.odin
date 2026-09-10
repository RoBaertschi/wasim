#+vet explicit-allocators
package wopt

Register     :: distinct u8
Register_Set :: bit_set[0..=63; u64]

INVALID_REGISTER :: Register(0xFF)

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
