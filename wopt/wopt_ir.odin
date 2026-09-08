#+vet explicit-allocators
package wopt

import "core:reflect"
import "core:io"
// SSA definition, based on the Go SSA: https://github.com/golang/go/tree/master/src/cmd/compile/internal/ssa

Operator :: enum {
	Argument,      // Argument <type> {param_index}
	Init_Memory,   // Init_Memory <mem>
	Const32,       // Const32 <i32> {immediate}
	Return,        // Return <none> values[0]
}

Value_Id :: distinct u32

VALUE_NONE :: Value_Id(0)

Value :: struct {
	id:       Value_Id,
	operator: Operator,
	type:     Type_Id,

	arguments: []Value_Id,
	immediate: u64, // just 8-bytes of memory, might be expanded for SIMD
}

Block_Kind :: enum {
	Exit,
}

Block_Id :: distinct u32

BLOCK_NONE :: Block_Id(0)

Block :: struct {
	id:      Block_Id,
	kind:    Block_Kind,
	control: Value_Id,
	values:  []Value_Id,
}

SSA_Print_Options :: struct {
	indent: string,
}

SSA_Printer :: struct {
	writer:  io.Writer,
	module:  ^Module,
	options: SSA_Print_Options,
}

ssa_write_type :: proc(p: ^SSA_Printer, type_id: Type_Id) -> (err: io.Error) {
	type := type_get(p.module, type_id)
	switch type.kind {
	case .None:   _, err = io.write_string(p.writer, "none")
	case .I32:    _, err = io.write_string(p.writer, "i32")
	case .Memory: _, err = io.write_string(p.writer, "mem")
	case .Struct:
		io.write_string(p.writer, "struct {") or_return
		for member in type.members {
			io.write_rune(p.writer, '[') or_return
			io.write_int(p.writer, member.offset) or_return
			io.write_string(p.writer, "] = ") or_return
			ssa_write_type(p, member.type) or_return
		}
		io.write_rune(p.writer, '}') or_return
	}

	return
}

ssa_write_value_id :: proc(p: ^SSA_Printer, value_id: Value_Id) -> (err: io.Error) {
	io.write_string(p.writer, "%v") or_return
	io.write_u64(p.writer, u64(value_id)) or_return
	return
}

_ssa_write_indent :: proc(p: ^SSA_Printer) -> (err: io.Error) {
	_, err = io.write_string(p.writer, p.options.indent)
	return
}

ssa_write_value :: proc(p: ^SSA_Printer, body: Function_Body, value_id: Value_Id) -> (err: io.Error) {
	value := body.values[value_id]

	_ssa_write_indent(p) or_return
	ssa_write_value_id(p, value_id) or_return
	io.write_string(p.writer, ": ") or_return
	ssa_write_type(p, value.type) or_return
	io.write_string(p.writer, " = ") or_return

	io.write_string(p.writer, reflect.enum_name_from_value(value.operator) or_else "invalid") or_return

	write_immediate :: proc(p: ^SSA_Printer, value: Value) -> (err: io.Error) {
		io.write_string(p.writer, " {") or_return
		io.write_u64(p.writer, value.immediate) or_return
		io.write_rune(p.writer, '}') or_return
		return
	}

	write_args :: proc(p: ^SSA_Printer, value: Value) -> (err: io.Error) {
		comma := " "
		for args in value.arguments {
			io.write_string(p.writer, comma) or_return
			ssa_write_value_id(p, args) or_return
			comma = ", "
		}

		return
	}

	Print_Flag  :: enum { Args, Immediate }
	Print_Flags :: bit_set[Print_Flag]

	@(static)
	LUT := #partial [Operator]Print_Flags{
		.Argument = { .Immediate },
		.Const32  = { .Immediate },

		.Return = { .Args },
	}

	print_flags := LUT[value.operator]
	if .Immediate in print_flags {
		write_immediate(p, value)
	}

	if .Args in print_flags {
		write_args(p, value)
	}

	io.write_rune(p.writer, '\n') or_return

	return
}

ssa_write_block :: proc(p: ^SSA_Printer, body: Function_Body, block_id: Block_Id) -> (err: io.Error) {
	block := body.blocks[block_id]

	io.write_rune(p.writer, 'b') or_return
	io.write_u64(p.writer, u64(block_id)) or_return

	switch block.kind {
	case .Exit:
		io.write_string(p.writer, " exit ") or_return
		ssa_write_value_id(p, block.control)
		io.write_string(p.writer, ":\n") or_return
	}

	for value in block.values {
		ssa_write_value(p, body, value) or_return
	}

	return
}

ssa_write_body :: proc(p: ^SSA_Printer, body: Function_Body) -> (err: io.Error) {
	for block in body.blocks[1:] {
		ssa_write_block(p, body, block.id) or_return
	}

	return
}

ssa_write_function_header :: proc(p: ^SSA_Printer, function: Function) -> (err: io.Error) {
	io.write_string(p.writer, function.name) or_return
	comma := " "
	for param in function.parameters {
		io.write_string(p.writer, comma) or_return
		ssa_write_type(p, param) or_return
		comma = ", "
	}
	io.write_string(p.writer, ":\n") or_return

	return
}

ssa_write_function_arguments :: proc(p: ^SSA_Printer, function: Function, body: Function_Body) -> (err: io.Error) {
	for _, i in function.parameters {
		ssa_write_value(p, body, Value_Id(i + 1)) or_return
	}

	return
}

ssa_write_function_build_body :: proc(p: ^SSA_Printer, function_id: Function_Id) -> (err: io.Error) {
	function := function_get(p.module, function_id)
	ssa_write_function_header(p, function) or_return
	ssa_write_function_arguments(p, function, function.build_body) or_return
	ssa_write_body(p, function.build_body) or_return

	return
}
