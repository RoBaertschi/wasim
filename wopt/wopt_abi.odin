#+vet explicit-allocators
package wopt

import B "../base"

ABI_Id :: distinct u32

ABI_NONE :: ABI_Id(0)

ABI_Procedure :: #type proc "c" (user_data: rawptr, parameters: []ABI_Value, result: ABI_Value) -> (caller_saved, callee_saved: Register_Set)

ABI :: struct {
	id:        ABI_Id,
	user_data: rawptr,
	procedure: ABI_Procedure,
}

ABI_Location_Flag :: enum {
	Indirect, // the scalar should be written to register[offset], where register contains a pointer
}

ABI_Location_Flags :: bit_set[ABI_Location_Flag; u8]

ABI_Location :: struct {
	offset:          int,                 // where in the specified location should we put the scalar
	indirect_offset: int,                 // where at the specified indirect offset should we put the scalar
	register:        Register,            // register or INVALID_REGISTER, if no register then offset is stack offset
	flags:           ABI_Location_Flags, // flags
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
