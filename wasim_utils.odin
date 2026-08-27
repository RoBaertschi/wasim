package wasim

import "base:intrinsics"

List :: struct($T: typeid)
	where intrinsics.type_has_field(T, "next"),
	      intrinsics.type_field_type(T, "next") == ^T{
	first, last: ^T,
	count:       int,
}

list_push :: proc(list: ^$L/List($T), node: ^T) {
	list.count += 1

	node.next = nil

	if intrinsics.unlikely(list.first == nil) {
		list.first = node
		list.last  = node
	} else {
		assert(list.last != nil)
		list.last.next = node
		list.last      = node
	}
}

list_concat :: proc(list: ^$L/List($T), append: ^L) {
	next := append.first.next if append.first != nil else nil
	for current := append.first; current != nil; current = next {
		next = current.next
		list_push(list, current)
	}
	append^ = {}
}
