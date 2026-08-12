package wasim

import "base:intrinsics"
List :: struct($T: typeid)
	where intrinsics.type_has_field(T, "next"),
	      intrinsics.type_field_type(T, "next") == ^T{
	first, last: ^T,
	count:       int,
}

list_push :: proc(list: ^List($T), node: ^T) {
	if intrinsics.unlikely(list.first == nil) {
		list.first = node
		list.last  = node
	} else {
		assert(list.last != nil)
		list.last.next = node
		list.last      = node
	}
}
