#+vet explicit-allocators
package wopt

// SSA definition, based on the Go SSA: https://github.com/golang/go/tree/master/src/cmd/compile/internal/ssa

Operator :: enum {
	Init_Memory,
	Memory_Tuple_Make,
	Select_Value,
	Select_Memory,
	Const32,
}

Value_Id :: distinct u32

Value :: struct {
	id:       Value_Id,
	operator: Operator,
	type:     Type_Id,

	immediate: u64, // just 8-bytes of memory, might be expanded for SIMD
}

Block_Kind :: enum {
	Exit,
}

Block_Id :: distinct u32

Block :: struct {
	id:      Block_Id,
	kind:    Block_Kind,
	control: Value_Id,
}
