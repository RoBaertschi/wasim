#+vet explicit-allocators
package wopt

ABI_Id :: distinct u32

ABI_Location_Kind :: enum {
	Register,
	Stack,
}

// Represents a range of
ABI_Location :: struct {
	kind:   ABI_Location_Kind,
	offset: int, // offset into the register or stack in bytes
}

ABI_Result :: struct {
	inputs: []ABI_Location,
	result: []ABI_Location,
}

usage :: proc() {
	when false {
		abi_clacify :: proc "c" (data: rawptr, parameters: []Type, result: Type) -> ABI_Result {
			return {}
		}
	}
}
