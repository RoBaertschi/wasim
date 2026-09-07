package cgen_example

// Deliberately declare the containing record before its element type.
@(tag="cabi")
Record :: struct {
	name: string,
	members: []Member,
	using summary: Summary,
}

@(tag="cabi")
Member :: struct {
	offset: int,
	id: Object_Id,
}

@(tag="cabi")
Summary :: struct {
	count: int,
}

@(tag="cabi")
record_identity :: proc(record: Record) -> Record {
	return record
}

@(tag="cabi")
member_sum :: proc(members: ..Member) -> uint {
	result: uint
	for member in members { result += uint(member.id) }
	return result
}

// Both forms exercise SSE register classification around padding.
@(tag="cabi")
Mixed :: struct { a: f32, b: f64 }

@(tag="cabi")
Tail :: struct { a: f64, b: f32 }

@(tag="cabi")
mixed_identity :: proc(value: Mixed) -> Mixed { return value }

@(tag="cabi")
tail_identity :: proc(value: Tail) -> Tail { return value }

@(tag="cabi")
mixed_pointer :: proc(value, output: ^Mixed) { output^ = value^ }

@(tag="cabi")
tail_pointer :: proc(value, output: ^Tail) { output^ = value^ }
