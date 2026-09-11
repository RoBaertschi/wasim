#+vet explicit-allocators
package wopt

import B "../base"

ABI_Id :: distinct u32

ABI_Location_Flag :: enum {
	Indirect, // goes loads a pointer and writes/reads from it
}

ABI_Location_Flags :: bit_set[ABI_Location_Flag; u8]

// Represents a location for a specific value
ABI_Location :: struct {
	type_index: int,
	offset:     int,      // offset into the register or stack in bytes
	register:   Register, // if register == INVALID_REGISTER then this is a stack location, else a register
	flags:      ABI_Location_Flags,
	_:          [6]u8, // explicit padding for consistent ABI behaviour
}

#assert(size_of(ABI_Location) == 24)

ABI_Data :: struct {
	parameters: []Type,
	result:     Type,
	inputs:     []ABI_Location,
	output:     []ABI_Location,
	clobbers:   Register_Set,
}

_abi_locations_push_from_type :: proc(m: ^Module, locations: ^[dynamic]ABI_Location, base_index: int, type: Type) -> int {
	base_index := base_index

	switch type.kind {
	case .Memory: // has no location
	case .None:   // has no location

	case .I32:
		append(locations, ABI_Location { type_index = base_index })
		base_index += 1
	case .Struct:
		for member in type.members {
			base_index = _abi_locations_push_from_type(m, locations, base_index, type_get(m, member.type))
		}
	}
	return base_index
}

_abi_locations_from_type :: proc(arena: ^B.Arena, m: ^Module, type: Type) -> []ABI_Location {
	locations: [dynamic]ABI_Location
	locations.allocator = B.arena_allocator(arena)

	_abi_locations_push_from_type(m, &locations, 0, type)

	shrink(&locations)
	return locations[:]
}

_abi_locations_from_type_id :: proc(arena: ^B.Arena, m: ^Module, type_id: Type_Id) -> []ABI_Location {
	return _abi_locations_from_type(arena, m, type_get(m, type_id))
}


_abi_type_from_type_with_index2 :: proc(m: ^Module, search_type: Type, index: int) -> (type: Type, ok: bool) {
	temp := B.TEMP_ALLOCATOR_GUARD()

	Stack_Item :: struct {
		type:           Type,
		current_member: int,
	}

	types_stack: [dynamic]Stack_Item
	types_stack.allocator = temp
	append(&types_stack, Stack_Item { search_type, 0 })

	current_index := 0

	loop: for 0 < len(types_stack) {
		top := &types_stack[len(types_stack)-1]
		switch top.type.kind {
		case .Struct:
			if top.current_member < len(top.type.members) {
				append(&types_stack, Stack_Item { type = type_get(m, top.type.members[top.current_member].type) })
				top.current_member += 1
			} else {
				pop(&types_stack)
			}
		case .None, .Memory:
		case .I32:
			if current_index == index {
				type = top.type
				ok   = true
				break loop
			}

			current_index += 1
			pop(&types_stack)
		}
	}

	return
}

_abi_type_from_type_with_index :: proc(m: ^Module, type: Type, current_index: int, find_index: int) -> (int, Type) {
	current_index := current_index

	switch type.kind {
	case .None:
	case .Memory:

	case .I32:
		if current_index == find_index {
			return current_index, {}
		}
		current_index += 1
	case .Struct:
		for member in type.members {
			found_type: Type
			current_index, found_type = _abi_type_from_type_with_index(m, type_get(m, member.type), current_index, find_index)
			if current_index == find_index {
				return current_index, found_type
			}
		}
	}

	return current_index, {}
}

ABI2_Location_Flag :: enum {
	Indirect, // the scalar should be written to register[offset], where register contains a pointer
}

ABI2_Location_Flags :: bit_set[ABI2_Location_Flag; u8]

ABI2_Location :: struct {
	offset:          int,                 // where in the specified location should we put the scalar
	indirect_offset: int,                 // where at the specified indirect offset should we put the scalar
	register:        Register,            // register or INVALID_REGISTER, if no register then offset is stack offset
	flags:           ABI2_Location_Flags, // flags
	_:               [size_of(int)-2]u8,  // padding to keep ABI explicit
}

#assert(size_of(ABI2_Location) == 24)

// TODO(robin): consider
// @(rodata)
// abi2_location_nil: ABI2_Location

// An ABI Value describes a type and it's representation in the ABI.
// The ABI is based on the scalars, so not structs but's it's struct members that are scalars.
// A struct just contains a type and the children, no location because it can't be stored anywhere.
// A scalar does not contain any children but a ABI Location. Which is used to describe where
// the scalar has to be read/written from/to.
ABI2_Value :: struct {
	type:     Type,
	children: []ABI2_Value,   // is type.members[i] == children[i].type
	location: ^ABI2_Location, // is nil if not an actual representable entity
}

_abi2_value_from_type :: proc(arena: ^B.Arena, m: ^Module, type: Type) -> (value: ABI2_Value) {
	value.type = type
	switch type.kind {
	case .None:
	case .Memory:
	case .Struct:
		value.children = B.arena_push_make(arena, []ABI2_Value, len(type.members))
		for member, i in type.members {
			value.children[i] = _abi2_value_from_type_id(arena, m, member.type)
		}
	case .I32:
		value.location = B.arena_push(arena, ABI2_Location)
	}
	return
}

_abi2_value_from_type_id :: proc(arena: ^B.Arena, m: ^Module, type_id: Type_Id) -> ABI2_Value {
	return _abi2_value_from_type(arena, m, type_get(m, type_id))
}

usage :: proc() {
	when false {
		abi_classify :: proc "c" (data: rawptr, parameters: []ABI2_Value, result: ABI2_Value) {
			return {}
		}
	}
}
