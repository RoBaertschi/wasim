package wasim

import "core:math/bits"
import "base:intrinsics"
import "core:mem/virtual"
import "core:flags"
import "core:os"
import "core:fmt"
import "core:encoding/varint"

MAGIC   :: u32(0x6D736100)
VERSION :: u32(1)

Binary_Reader :: struct {
	data:   []byte,
	pos:    int,
	file:   string,
	m:      ^Module,
	bounds: Rng1(int),

	errors: int,
}

reader_push_bounds :: proc(r: ^Binary_Reader, bounds: Rng1(int)) -> (old_bounds: Rng1(int)) {
	old_bounds = r.bounds
	r.bounds   = rng1_clamp_to_slice(bounds, rng1_slice(r.bounds, r.data))
	return
}

reader_pop_bounds :: proc(r: ^Binary_Reader, old_bounds: Rng1(int)) {
	r.bounds = old_bounds
}

_reader_end_bounds :: proc(r: ^Binary_Reader, _, old_bounds: Rng1(int)) {
	reader_pop_bounds(r, old_bounds)
}

@(deferred_in_out=_reader_end_bounds)
reader_bounds_guard :: proc(r: ^Binary_Reader, bounds: Rng1(int)) -> (old_bounds: Rng1(int)) {
	return reader_push_bounds(r, bounds)
}

Section_Kind :: enum byte {
	Custom,
	Type,
	Import,
	Function,
	Table,
	Memory,
	Global,
	Export,
	Start,
	Element,
	Code,
	Data,
}

Value_Type :: enum byte {
	I32,
	I64,
	U32,
	U64,
}

Function_Type :: struct {
	args: []Value_Type,
	rets: []Value_Type,
}

Type_Index :: distinct u32

Code :: struct {
	size: int,
}

Section :: struct {
	kind:  Section_Kind,
	size:  int,
	types: []Function_Type,
	funcs: []Type_Index,
	codes: []Code,
}

Section_Node :: struct {
	next:    ^Section_Node,
	section: Section,
}

Section_List :: List(Section_Node)

Module :: struct {
	arena:    virtual.Arena,
	version:  int,
	sections: Section_List,
}

errorf :: proc(r: ^Binary_Reader, pos: int, format: string, args: ..any) {
	r.errors += 1

	fmt.printf("%v:%v: WASM Binary Error: ", r.file, pos)
	fmt.printfln(format, ..args)
}

reader_relative_pos :: proc(r: ^Binary_Reader) -> int {
	return r.pos - r.bounds.start
}

reader_bounded_data :: proc(r: ^Binary_Reader) -> []byte {
	return rng1_slice(r.bounds, r.data)
}

reader_data_left :: proc(r: ^Binary_Reader) -> int {
	return len(rng1_slice(r.bounds, r.data)) - reader_relative_pos(r)
}

read_bytes :: proc(r: ^Binary_Reader, count: int) -> (bytes: []byte, ok: bool) {
	if count <= reader_data_left(r) {
		pos   := reader_relative_pos(r)
		bytes  = rng1_slice(r.bounds, r.data)[pos:pos+count]
		ok     = true

		r.pos += count
	} else {
		errorf(r, r.pos, "missing bytes")
	}

	return
}

read_t :: proc(r: ^Binary_Reader, $T: typeid) -> (value: T, ok: bool) {
	data: []byte
	data, ok = read_bytes(r, size_of(T))

	if ok {
		value = (^T)(raw_data(data))^
	}

	return
}

read_u32 :: proc(r: ^Binary_Reader) -> (u32, bool) { return read_t(r, u32) }

read_byte :: proc(r: ^Binary_Reader) -> (result: u8, ok: bool) {
	if 1 <= reader_data_left(r) {
		pos    := reader_relative_pos(r)
		result  = rng1_slice(r.bounds, r.data)[pos]
		ok      = true
		r.pos  += 1
	} else {
		errorf(r, r.pos, "missing byte")
	}

	return
}

read_uXX_leb :: proc(r: ^Binary_Reader, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: u128(max(T))

	value_u128, size, err := varint.decode_uleb128_buffer(rng1_slice(r.bounds, r.data)[reader_relative_pos(r):])
	switch err {
	case .None:
		// validate LEB u32 size
		if size <= MAX_BYTES {
			if value_u128 <= MAX {
				// valid LEB u32 found
				ok     = true
				value  = T(value_u128)
				r.pos += size
			} else {
				errorf(r, r.pos, "LEB %[0]v has value to large to fit into a %[0]v: %v <= %v", typeid_of(T), value_u128, MAX)
			}
		} else {
			errorf(r, r.pos, "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: errorf(r, r.pos, "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  errorf(r, r.pos, "LEB to large to even fit into a u128")
	}

	return
}

read_u32_leb :: proc(r: ^Binary_Reader) -> (value: u32, ok: bool) { return read_uXX_leb(r, u32) }

as :: proc($T: typeid, a: $A, ok: bool) -> (T, bool) {
	return (T)(a), ok
}

read_vec :: proc(r: ^Binary_Reader, parse_proc: proc(r: ^Binary_Reader) -> ($T, bool)) -> (data: []T, ok: bool) {
	size: u32
	size, ok = read_u32_leb(r)
	if ok {
		data, _ = virtual.make(&r.m.arena, []T, size)

		for i in 0..<size {
			data[i], ok = parse_proc(r)
			if !ok {
				break
			}
		}
	}

	return
}

read_value_type :: proc(r: ^Binary_Reader) -> (value_type: Value_Type, ok: bool) {
	value_type_byte: byte
	value_type_byte, ok = read_byte(r)

	if ok {
		if value_type_byte <= byte(max(Value_Type)) {
			value_type = Value_Type(value_type_byte)
		} else {
			errorf(r, r.pos - 1, "invalid value type %v: %v(0) <= %v(%v)", value_type_byte, min(Value_Type), max(Value_Type), byte(max(Value_Type)))
		}
	}

	return
}

read_func_type :: proc(r: ^Binary_Reader) -> (type: Function_Type, ok: bool) {
	identify_byte: byte
	identify_byte, ok = read_byte(r)
	if ok {
		FUNCTION_TYPE_IDENTIFY_BYTE :: 0x60

		if identify_byte == FUNCTION_TYPE_IDENTIFY_BYTE {
			type.args, ok = read_vec(r, read_value_type)
			if ok {
				type.rets, ok = read_vec(r, read_value_type)
			}
		} else {
			ok = false
			errorf(
				r,
				r.pos - 1,
				"expected identifying byte for function, but got unknown one: %v != FUNCTION_TYPE_IDENTIFY_BYTE(%v)",
				identify_byte,
				FUNCTION_TYPE_IDENTIFY_BYTE,
			)
		}
	}

	return
}

read_code :: proc(r: ^Binary_Reader) -> (code: Code, ok: bool) {
	code.size, ok = as(int, read_u32_leb(r))
	if ok {
		if reader_relative_pos(r) + code.size <= len(reader_bounded_data(r)) {
			r.pos += code.size
		} else {
			ok = false
			errorf(r, r.pos, "out of bounds code size, pos(%v) + size(%v) in bounds %v", r.pos, code.size, r.bounds)
		}
	}

	return
}

read_type_section :: proc(r: ^Binary_Reader) -> (types: []Function_Type, ok: bool) {
	types, ok = read_vec(r, read_func_type)
	return
}

read_func_section :: proc(r: ^Binary_Reader) -> (funcs: []Type_Index, ok: bool) {
	funcs, ok = read_vec(r, proc(r: ^Binary_Reader) -> (type_index: Type_Index, ok: bool) { return as(Type_Index, read_u32_leb(r)) })
	return
}

read_code_section :: proc(r: ^Binary_Reader) -> (codes: []Code, ok: bool) {
	codes, ok = read_vec(r, read_code)
	return
}

read_section :: proc(r: ^Binary_Reader) -> (section: Section, ok: bool) {
	section.kind, ok = read_t(r, Section_Kind)
	if ok {
		if u8(section.kind) <= u8(max(Section_Kind)) {
			section.size, ok = as(int, read_u32_leb(r))
			if ok {
				reader_bounds_guard(r, rng1(r.pos, r.pos+section.size))

				switch section.kind {
				case .Custom: // do nothing
				case .Type:     section.types, ok = read_type_section(r)
				case .Import:   // unimplemented()
				case .Function: section.funcs, ok = read_func_section(r)
				case .Table:    // unimplemented()
				case .Memory:   // unimplemented()
				case .Global:   // unimplemented()
				case .Export:   // unimplemented()
				case .Start:    // unimplemented()
				case .Element:  // unimplemented()
				case .Code:     section.codes, ok = read_code_section(r)
				case .Data:     // unimplemented()
				}
			}
		} else {
			ok = false
			errorf(r, r.pos, "invalid section kind %d, expected 0..=%v", u8(section.kind), u8(max(Section_Kind)))
		}
	}

	return
}

read_sections_into_module :: proc(r: ^Binary_Reader) -> (ok: bool) {
	ok = true

	for r.pos < len(r.data) {
		section: Section
		section, ok = read_section(r)
		if ok {
			node, _ := virtual.new(&r.m.arena, Section_Node)
			node.section = section
			list_push(&r.m.sections, node)
		} else {
			break
		}
	}

	return
}

read_module :: proc(r: ^Binary_Reader) -> (ok: bool) {
	r.m, _   = virtual.arena_growing_bootstrap_new(Module, "arena")
	r.bounds = rng1(0, len(r.data))

	// read magic number
	magic: u32
	magic, ok = read_u32(r)
	if ok {
		if magic == MAGIC {

			// read version number
			version: u32
			version, ok = read_u32(r)
			if ok {
				if version == VERSION {
					// read sections
					ok = read_sections_into_module(r)

					if ok {
						fmt.printfln("found module with version %v", version)
						for section_node := r.m.sections.first; section_node != nil; section_node = section_node.next {
							section := section_node.section
							fmt.printfln("found section of type %v", section)
						}
					}
				} else {
					ok = false
					errorf(r, r.pos-size_of(version), "unsupported WASM version %v, currently only WASM 1.0 is supported", version)
				}
			}
		} else {
			ok = false
			errorf(r, r.pos-size_of(magic), "invalid magic number %v, expected %v", magic, MAGIC)
		}
	}

	return
}

main :: proc() {
	Cmd :: struct {
		input_module: ^os.File `args:"pos=0,required"`,
	}

	cmd: Cmd

	flags.parse_or_exit(&cmd, os.args, allocator = context.temp_allocator)

	data, err := os.read_entire_file(cmd.input_module, context.temp_allocator)
	if err == nil {
		r := Binary_Reader {
			data = data,
			file = os.name(cmd.input_module),
		}

		read_module(&r)
	} else {
		fmt.eprintfln("could not read file %q: %v", os.name(cmd.input_module), err)
	}
}
