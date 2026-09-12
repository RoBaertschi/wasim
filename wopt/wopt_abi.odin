#+vet explicit-allocators
package wopt

import B "../base"

// An Id to refer to a specific ABI.
//
// An ABI currently defines the calling convention of a function. It's an interface so that any user can add large variations of
// different calling conventions. The ABI informs per function the backend about where specific inputs and outputs are/go.
// The stack is defined in the argument stack, which is a area of size `ABI_Config.argument_stack_size` that is setup directly
// before the call instruction. So on AMD64, the return address is pushed after it. The stack will be aligned by the backend
// to `ABI_Config.align_stack_to` bytes. Note that it is aligned to that before the call, so the return address pushed by call
// might dealign it again, which is expected. The ABI also specifies which registers a caller needs to retain (the call clobbers them)
// and which the callee has to retain (the old ones need to be spilled and restored later on).
//
// The inputs/output are a list of `ABI_Value`s that contain the type of the value, it's children (for structs) and optionally an
// `ABI_Location` pointer. Only scalars (i32) contain a location, no struct can have a location. Locations are provided by the
// backend so that the ABI procedure does not have to allocate anything that the backend uses (makes memory management easier).
// This might have to change in the future because we might need to support multiple location scalars like 128-bit integers.
//
// TODO(robin, 20260912-110007): lift the requirement of one ABI Location per Value
ABI_Id :: distinct u32

ABI_NONE :: ABI_Id(0)

ABI_Config :: struct {
	caller_saved:        Register_Set,
	callee_saved:        Register_Set,
	align_stack_to:      int,
	argument_stack_size: int,
}

ABI_Procedure :: #type proc "c" (user_data: rawptr, parameters: []ABI_Value, result: ABI_Value) -> (config: ABI_Config)

ABI :: struct {
	id:        ABI_Id,
	user_data: rawptr,
	procedure: ABI_Procedure,
}

ABI_Location_Flag :: enum {
	Indirect, // the scalar should be written to register[offset], where register contains a pointer
}

ABI_Location_Flags :: bit_set[ABI_Location_Flag; u8]

// An ABI location describes the place a specific `ABI_Value` lifes.
// It can either life on the argument stack or in an argument.
// The argument stack is a area of stack right before the call instruction.
//
// TODO(robin, 20260912-110007): lift the requirement of one ABI Location per Value
// TODO(robin, 20260828-211721): adjust for multiple architectures
ABI_Location :: struct {
	offset:          int,                 // where in the specified location should we put the scalar
	indirect_offset: int,                 // where at the specified indirect offset should we put the scalar
	register:        Register,            // register or INVALID_REGISTER, if no register then offset is stack offset
	flags:           ABI_Location_Flags,  // flags
	_:               [size_of(int)-2]u8,  // padding to keep ABI explicit
}

#assert(size_of(ABI_Location) == 24)

// TODO(robin): consider
// @(rodata)
// abi_location_nil: ABI_Location

// An ABI Value describes a type and it's representation in the ABI.
// The ABI is based on the scalars, so not structs but's it's struct members that are scalars.
// A struct just contains a type and the children, no location because it can't be stored anywhere.
// A scalar does not contain any children but a ABI Location. Which is used to describe where
// the scalar has to be read/written from/to.
ABI_Value :: struct {
	type:     Type,
	children: []ABI_Value,   // is type.members[i] == children[i].type
	location: ^ABI_Location, // is nil if not an actual representable entity
}

_abi_value_from_type :: proc(arena: ^B.Arena, m: ^Module, type: Type) -> (value: ABI_Value) {
	value.type = type
	switch type.kind {
	case .None:
	case .Memory:
	case .Struct:
		value.children = B.arena_push_make(arena, []ABI_Value, len(type.members))
		for member, i in type.members {
			value.children[i] = _abi_value_from_type_id(arena, m, member.type)
		}
	case .I32:
		value.location = B.arena_push(arena, ABI_Location)
	}
	return
}

_abi_value_from_type_id :: proc(arena: ^B.Arena, m: ^Module, type_id: Type_Id) -> ABI_Value {
	return _abi_value_from_type(arena, m, type_get(m, type_id))
}

usage :: proc() {
	when false {
		abi_classify :: proc "c" (data: rawptr, parameters: []ABI_Value, result: ABI_Value) -> (clobbers: Register_Set) {
			return {}
		}
	}
}
