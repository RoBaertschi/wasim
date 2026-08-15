package wasim

import "core:os"
import "core:fmt"
import "core:flags"
import "core:encoding/varint"

import "base:intrinsics"

import B "base"

MAGIC   :: u32(0x6D736100)
VERSION :: u32(1)

Byte_Range :: B.Rng1(int)

Diagnostic :: struct {
	next:  ^Diagnostic,
	error: string,
	range: Byte_Range,
}

Diagnostic_List :: distinct List(Diagnostic)

Read_Ctx :: struct {
	base: int,    // base offset into file
	curr: int,    // current offset into data
	data: []byte, // slice inside file (does not need to be the whole file)
	digs: Diagnostic_List,

	file: string,
	errors: int,
	m: ^Module,
}

reader_push_data :: proc(ctx: ^Read_Ctx, count: int) -> (old_base, resume_curr: int, old_data: []byte, ok: bool) {
	if count < 0 || count > reader_data_left(ctx) {
		errorf(ctx, ctx.base+ctx.curr, "missing bytes")
		return
	}

	old_base    = ctx.base
	old_data    = ctx.data
	resume_curr = ctx.curr + count

	ctx.base += ctx.curr
	ctx.curr  = 0
	ctx.data  = old_data[resume_curr-count:resume_curr]
	ok        = true
	return
}

reader_pop_data :: proc(ctx: ^Read_Ctx, old_base, resume_curr: int, old_data: []byte) {
	ctx.base = old_base
	ctx.curr = resume_curr
	ctx.data = old_data
}

_reader_end_data :: proc(ctx: ^Read_Ctx, _: int, old_base, resume_curr: int, old_data: []byte, ok: bool) {
	if ok {
		reader_pop_data(ctx, old_base, resume_curr, old_data)
	}
}

@(deferred_in_out=_reader_end_data)
reader_data_guard :: proc(ctx: ^Read_Ctx, count: int) -> (old_base, resume_curr: int, old_data: []byte, ok: bool) {
	return reader_push_data(ctx, count)
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
	pos:   int,
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
	arena:    ^B.Arena,
	arenas:   []^B.Arena,
	version:  u32,
	sections: []Section,
}

errorf :: proc(ctx: ^Read_Ctx, pos: int, format: string, args: ..any) {
	ctx.errors += 1

	fmt.printf("%v:%v: WASM Binary Error: ", ctx.file, pos)
	fmt.printfln(format, ..args)
}

reader_data_left :: proc(ctx: ^Read_Ctx) -> int {
	return len(ctx.data) - ctx.curr
}

read_bytes :: proc(ctx: ^Read_Ctx, count: int) -> (bytes: []byte, ok: bool) {
	if count <= reader_data_left(ctx) {
		pos   := ctx.curr
		bytes  = ctx.data[pos:pos+count]
		ok     = true

		ctx.curr += count
	} else {
		errorf(ctx, ctx.base+ctx.curr, "missing bytes")
	}

	return
}

read_t :: proc(ctx: ^Read_Ctx, $T: typeid) -> (value: T, ok: bool) {
	data: []byte
	data, ok = read_bytes(ctx, size_of(T))

	if ok {
		value = (^T)(raw_data(data))^
	}

	return
}

read_u32 :: proc(ctx: ^Read_Ctx) -> (u32, bool) { return read_t(ctx, u32) }

read_byte :: proc(ctx: ^Read_Ctx) -> (result: u8, ok: bool) {
	if 1 <= reader_data_left(ctx) {
		result    = ctx.data[ctx.curr]
		ok        = true
		ctx.curr += 1
	} else {
		errorf(ctx, ctx.base+ctx.curr, "missing byte")
	}

	return
}

read_uXX_leb :: proc(ctx: ^Read_Ctx, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: u128(max(T))

	value_u128, size, err := varint.decode_uleb128_buffer(ctx.data[ctx.curr:])
	switch err {
	case .None:
		// validate LEB u32 size
		if size <= MAX_BYTES {
			if value_u128 <= MAX {
				// valid LEB u32 found
				ok     = true
				value  = T(value_u128)
				ctx.curr += size
			} else {
				errorf(ctx, ctx.base+ctx.curr, "LEB %[0]v has value to large to fit into a %[0]v: %v <= %v", typeid_of(T), value_u128, MAX)
			}
		} else {
			errorf(ctx, ctx.base+ctx.curr, "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: errorf(ctx, ctx.base+ctx.curr, "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  errorf(ctx, ctx.base+ctx.curr, "LEB to large to even fit into a u128")
	}

	return
}

read_u32_leb :: proc(ctx: ^Read_Ctx) -> (value: u32, ok: bool) { return read_uXX_leb(ctx, u32) }

as :: proc($T: typeid, a: $A, ok: bool) -> (T, bool) {
	return (T)(a), ok
}

read_vec :: proc(ctx: ^Read_Ctx, parse_proc: proc(ctx: ^Read_Ctx) -> ($T, bool)) -> (data: []T, ok: bool) {
	size: u32
	size, ok = read_u32_leb(ctx)
	if ok {
		data = B.arena_push_make(ctx.m.arena, []T, size)

		for i in 0..<size {
			data[i], ok = parse_proc(ctx)
			if !ok {
				break
			}
		}
	}

	return
}

read_value_type :: proc(ctx: ^Read_Ctx) -> (value_type: Value_Type, ok: bool) {
	value_type_byte: byte
	value_type_byte, ok = read_byte(ctx)

	if ok {
		if value_type_byte <= byte(max(Value_Type)) {
			value_type = Value_Type(value_type_byte)
		} else {
			errorf(ctx, ctx.base + ctx.curr - 1, "invalid value type %v: %v(0) <= %v(%v)", value_type_byte, min(Value_Type), max(Value_Type), byte(max(Value_Type)))
		}
	}

	return
}

read_func_type :: proc(ctx: ^Read_Ctx) -> (type: Function_Type, ok: bool) {
	identify_byte: byte
	identify_byte, ok = read_byte(ctx)
	if ok {
		FUNCTION_TYPE_IDENTIFY_BYTE :: 0x60

		if identify_byte == FUNCTION_TYPE_IDENTIFY_BYTE {
			type.args, ok = read_vec(ctx, read_value_type)
			if ok {
				type.rets, ok = read_vec(ctx, read_value_type)
			}
		} else {
			ok = false
			errorf(
				ctx,
				ctx.base + ctx.curr - 1,
				"expected identifying byte for function, but got unknown one: %v != FUNCTION_TYPE_IDENTIFY_BYTE(%v)",
				identify_byte,
				FUNCTION_TYPE_IDENTIFY_BYTE,
			)
		}
	}

	return
}

read_code :: proc(ctx: ^Read_Ctx) -> (code: Code, ok: bool) {
	code.size, ok = as(int, read_u32_leb(ctx))
	if ok {
		if ctx.curr + code.size <= len(ctx.data) {
			ctx.curr += code.size
		} else {
			ok = false
			errorf(ctx, ctx.base + ctx.curr, "out of bounds code size, pos(%v) + size(%v) in bounds %v", ctx.base + ctx.curr, code.size, B.rng1(ctx.base, ctx.base+len(ctx.data)))
		}
	}

	return
}

read_type_section :: proc(ctx: ^Read_Ctx) -> (types: []Function_Type, ok: bool) {
	types, ok = read_vec(ctx, read_func_type)
	return
}

read_func_section :: proc(ctx: ^Read_Ctx) -> (funcs: []Type_Index, ok: bool) {
	funcs, ok = read_vec(ctx, proc(ctx: ^Read_Ctx) -> (type_index: Type_Index, ok: bool) { return as(Type_Index, read_u32_leb(ctx)) })
	return
}

read_code_section :: proc(ctx: ^Read_Ctx) -> (codes: []Code, ok: bool) {
	codes, ok = read_vec(ctx, read_code)
	return
}

read_section :: proc(ctx: ^Read_Ctx) -> (section: Section, ok: bool) {
	section.kind, ok = read_t(ctx, Section_Kind)
	if ok {
		if u8(section.kind) <= u8(max(Section_Kind)) {
			section.size, ok = as(int, read_u32_leb(ctx))
			if ok {
				reader_data_guard(ctx, section.size) or_return

				switch section.kind {
				case .Custom: // do nothing
				case .Type:     section.types, ok = read_type_section(ctx)
				case .Import:   // unimplemented()
				case .Function: section.funcs, ok = read_func_section(ctx)
				case .Table:    // unimplemented()
				case .Memory:   // unimplemented()
				case .Global:   // unimplemented()
				case .Export:   // unimplemented()
				case .Start:    // unimplemented()
				case .Element:  // unimplemented()
				case .Code:     section.codes, ok = read_code_section(ctx)
				case .Data:     // unimplemented()
				}
			}
		} else {
			ok = false
			errorf(ctx, ctx.base + ctx.curr, "invalid section kind %d, expected 0..=%v", u8(section.kind), u8(max(Section_Kind)))
		}
	}

	return
}

read_sections_into_module :: proc(ctx: ^Read_Ctx) -> (ok: bool) {
	// ok = true
	//
	// for ctx.curr < len(ctx.data) {
	// 	section: Section
	// 	section, ok = read_section(ctx)
	// 	if ok {
	// 		node := B.arena_push(ctx.m.arena, Section_Node)
	// 		node.section = section
	// 		list_push(&ctx.m.sections, node)
	// 	} else {
	// 		break
	// 	}
	// }
	//
	// return
	return
}

read_module :: proc(ctx: ^Read_Ctx) -> (ok: bool) {
	if B.lane_idx() == 0 {
		ctx.m        = B.arena_bootstrap_new(Module, "arena")
		ctx.m.arenas = B.arena_push_make(ctx.m.arena, []^B.Arena, B.lane_count())

		// read magic number
		magic: u32
		magic, ok = read_u32(ctx)
		if ok {
			if magic == MAGIC {
				ok = true
			} else {
				ok = false
				errorf(ctx, ctx.base+ctx.curr-size_of(magic), "invalid magic number %v, expected %v", magic, MAGIC)
			}
		}

		// read version number
		if ok {
			ctx.m.version, ok = read_u32(ctx)
			if ctx.m.version == VERSION {
				ok = true
			} else {
				ok = false
				errorf(ctx, ctx.base+ctx.curr-size_of(u32), "unsupported WASM version %v, currently only WASM 1.0 is supported", ctx.m.version)
			}
		}

		// fast-collect all sections for parallel processing
		section_list: Section_List
		if ok {
			for ctx.curr < len(ctx.data) {
				section: Section

				section.kind, ok = read_t(ctx, Section_Kind)
				if !ok {
					break
				}

				ok = u8(section.kind) <= u8(max(Section_Kind))
				if !ok {
					break
				}

				section.size, ok = as(int, read_u32_leb(ctx))
				if !ok {
					break
				}

				node         := B.arena_push(ctx.m.arena, Section_Node)
				node.section  = section
				list_push(&section_list, node)
			}
		}

		// collect all sections into a linear array
		if ok {
			ctx.m.sections = B.arena_push_make(ctx.m.arena, []Section, section_list.count)

			i := 0
			for current := section_list.first; current != nil; current = current.next {
				ctx.m.sections[i] = current.section

				i += 1
			}
		}
	}

	B.lane_sync_value(&ok, 0)

	if !ok {
		return
	}

	ctx.m.arenas[B.lane_idx()] = B.arena_alloc()
	B.lane_sync()

	section_list: Section_List

	// read sections
	ok = read_sections_into_module(ctx)

	if ok {
		fmt.printfln("found module with version %v", ctx.m.version)
		for section_node := section_list.first; section_node != nil; section_node = section_node.next {
			section := section_node.section
			fmt.printfln("found section of type %q: %v", section.kind, section)
		}
	}

	return
}

read_entry_point :: proc() {}

main :: proc() {
	B.inst_begin_profile()
	defer B.inst_end_profile()

	Cmd :: struct {
		input_module: ^os.File `args:"pos=0,required"`,
	}

	cmd: Cmd

	flags.parse_or_exit(&cmd, os.args, allocator = context.temp_allocator)

	data, err := os.read_entire_file(cmd.input_module, context.temp_allocator)
	if err == nil {
		ctx := Read_Ctx {
			data = data,
			file = os.name(cmd.input_module),
		}

		read_module(&ctx)
	} else {
		fmt.eprintfln("could not read file %q: %v", os.name(cmd.input_module), err)
	}
}
