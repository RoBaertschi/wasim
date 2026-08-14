package wasim_base

import "base:intrinsics"

sll_insert :: #force_inline proc(first, last: ^^$T, value: ^T)
	where intrinsics.type_has_field(T, "next"), intrinsics.type_field_type(T, "next") == ^T
{
	if last^ == nil {
		first^ = value
		last^  = value
	} else {
		last^.next = value
		last^      = value
	}
}

dll_remove :: #force_inline proc(prev, next: ^^$T)
	where intrinsics.type_has_field(T, "next"), intrinsics.type_field_type(T, "next") == ^T,
	      intrinsics.type_has_field(T, "prev"), intrinsics.type_field_type(T, "prev") == ^T
{
	if prev^ != nil {
		prev^.next = next^
	}

	if next^ != nil {
		next^.prev = prev^
	}

	prev^ = nil
	next^ = nil
}

dll_insert_front :: #force_inline proc(first, last: ^^$T, node: ^T)
	where intrinsics.type_has_field(T, "next"), intrinsics.type_field_type(T, "next") == ^T,
	      intrinsics.type_has_field(T, "prev"), intrinsics.type_field_type(T, "prev") == ^T
{
	if last^ == nil {
		first^ = node
		last^  = node
	} else {
		node.next   = first^
		first^.prev = node
		first^      = node
	}
}
