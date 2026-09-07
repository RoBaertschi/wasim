package cgen_example

@(tag="cabi")
Object_Id :: distinct uint

@(tag="cabi")
Kind :: enum { None, Ready, Done }

@(tag="cabi")
Flag :: enum { A = 4, B, C }

@(tag="cabi")
Flags :: bit_set[Flag]

@(tag="cabi")
Padded :: struct {
	a: u8,
	b: u64,
}

@(tag="cabi")
Nested :: struct {
	inner: Padded,
	count: i32,
}

@(tag="cabi_opaque")
Object :: struct {
	id: Object_Id,
}

@(tag="cabi")
object_new :: proc(id: Object_Id) -> ^Object {
	object := new(Object)
	object.id = id
	return object
}

@(tag="cabi")
object_free :: proc(object: ^Object) {
	free(object)
}

@(tag="cabi")
object_kind :: proc(object: ^Object, kind: Kind = .Ready, flags := Flags{.A}) -> u32 {
	return u32(object.id) + u32(kind) + u32(transmute(u8) flags)
}

@(tag="cabi")
sum_bytes :: proc(bytes: []u8) -> u32 {
	total: u32
	for byte in bytes { total += u32(byte) }
	return total
}

@(tag="cabi")
sum_variadic :: proc(values: ..i32) -> i32 {
	total: i32
	for value in values { total += value }
	return total
}

// Grouped parameters, variadics, and an inferred default, as in wopt's constructors.
@(tag="cabi")
sum_with_flags :: proc(a, b: i32, values: ..i32, flags := Flags{}) -> i32 {
	return a + b + sum_variadic(..values) + i32(transmute(u8)flags)
}

@(tag="cabi")
echo_bytes :: proc(value: string) -> string {
	return value
}

@(tag="cabi")
identity_bytes :: proc(value: []u8) -> []u8 {
	return value
}

@(tag="cabi")
pair_string_bytes :: proc(value: string, bytes: []u8) -> (string, []u8) {
	return value, bytes
}

@(tag="cabi")
move_padded :: proc(value: Padded) -> Padded {
	return value
}

@(tag="cabi")
move_padded_ptr :: proc(value: ^Padded, output: ^Padded) {
	output^ = value^
}

@(tag="cabi")
move_nested :: proc(value: Nested) -> Nested {
	return value
}

@(tag="cabi")
move_nested_ptr :: proc(value: ^Nested, output: ^Nested) {
	output^ = value^
}

@(tag="cabi")
split :: proc(value: i32) -> (i32, i32) {
	return value, value * 2
}
