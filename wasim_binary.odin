package wasim

import "core:os"
import "core:fmt"
import "core:sync"
import "core:flags"
import "core:thread"
import "core:strings"
import "core:sys/info"
import "core:encoding/varint"

import "base:runtime"
import "base:intrinsics"

import B "base"

import T "tracy"

BIN_MAGIC   :: u32(0x6D736100)
BIN_SUPPORTED_VERSION :: u32(1)

Byte_Range :: B.Rng1(int)

Diagnostic :: struct {
	error: string,
	range: Byte_Range,
}

Diagnostic_Node :: struct {
	next: ^Diagnostic_Node,
	diag: Diagnostic,
}

Diagnostic_List :: distinct List(Diagnostic_Node)

diag_list_push :: proc(a: ^B.Arena, l: ^Diagnostic_List, diag: Diagnostic) {
	node      := B.arena_push(a, Diagnostic_Node)
	node.diag  = diag
	list_push(l, node)
}

Read_Ctx :: struct {
	base: int,    // base offset into file
	curr: int,    // current offset into data
	data: []byte, // slice inside file (does not need to be the whole file)
	digs: Diagnostic_List,

	arena: ^B.Arena,
}

reader_set_scope :: proc(ctx: ^Read_Ctx, base: int, data: []byte) {
	ctx.base = base
	ctx.curr = 0
	ctx.data = data
}

reader_push_data :: proc(ctx: ^Read_Ctx, count: int) -> (old_base, resume_curr: int, old_data: []byte, ok: bool) {
	start     := reader_anchor(ctx)
	data_left := reader_data_left(ctx)

	if count < 0 || data_left < count {
		errorf(ctx, B.rng1(start, start+data_left), "missing %v bytes", count-data_left)
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

Bin_Section_Kind :: enum byte {
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

Bin_Section :: struct {
	kind: Bin_Section_Kind,
	pos:  int,
	data: []byte,
}

Bin_Section_Node :: struct {
	next:    ^Bin_Section_Node,
	section: Bin_Section,
}

Bin_Code :: struct {
	pos:  int,
	data: []byte,
}


Section_List :: List(Bin_Section_Node)

Bin_Module :: struct {
	version: u32,
	sections: []Bin_Section,
	code_section_index: int,
}

reader_arena :: proc(ctx: ^Read_Ctx) -> ^B.Arena {
	return ctx.arena
}

reader_allocator :: proc(ctx: ^Read_Ctx) -> runtime.Allocator {
	return B.arena_allocator(reader_arena(ctx))
}

errorf :: proc(ctx: ^Read_Ctx, range: Byte_Range, format: string, args: ..any) {
	diag := Diagnostic {
		error = fmt.aprintf(format, ..args, allocator = reader_allocator(ctx)),
		range = range,
	}

	diag_list_push(reader_arena(ctx), &ctx.digs, diag)
}

reader_absolute_pos :: proc(ctx: ^Read_Ctx) -> int {
	return ctx.base + ctx.curr
}

reader_anchor :: reader_absolute_pos

reader_anchor_range :: proc(ctx: ^Read_Ctx, anchor: int) -> (result: Byte_Range) {
	result.start = anchor
	result.end   = reader_anchor(ctx)
	assert(result.start <= result.end)
	return
}

reader_data_left :: proc(ctx: ^Read_Ctx) -> int {
	return len(ctx.data) - ctx.curr
}

read_bytes :: proc(ctx: ^Read_Ctx, count: int) -> (bytes: []byte, ok: bool) {
	start     := reader_anchor(ctx)
	data_left := reader_data_left(ctx)

	if count <= data_left {
		pos   := ctx.curr
		bytes  = ctx.data[pos:pos+count]
		ok     = true

		ctx.curr += count
	} else {
		errorf(ctx, B.rng1(start, start+data_left), "missing %v bytes", count-data_left)
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
read_u64 :: proc(ctx: ^Read_Ctx) -> (u64, bool) { return read_t(ctx, u64) }

read_byte :: proc(ctx: ^Read_Ctx) -> (result: u8, ok: bool) {
	start := reader_anchor(ctx)

	if 1 <= reader_data_left(ctx) {
		result    = ctx.data[ctx.curr]
		ok        = true
		ctx.curr += 1
	} else {
		errorf(ctx, reader_anchor_range(ctx, start), "missing byte")
	}

	return
}

read_iXX_leb :: proc(ctx: ^Read_Ctx, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), !intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: i128(max(T))
	MIN       :: i128(min(T))

	start := reader_anchor(ctx)

	value_i128, size, err := varint.decode_ileb128_buffer(ctx.data[ctx.curr:])
	switch err {
	case .None:
		// validate LEB u32 size
		if size <= MAX_BYTES {
			if MIN <= value_i128 && value_i128 <= MAX {
				// valid LEB u32 found
				ok     = true
				value  = T(value_i128)
				ctx.curr += size
			} else {
				errorf(ctx, reader_anchor_range(ctx, start), "LEB %[0]v has value that does not fit into a %[0]v: MIN(%v) <= %v <= MAX(%v)", typeid_of(T), MIN, value_i128, MAX)
			}
		} else {
			errorf(ctx, reader_anchor_range(ctx, start), "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: errorf(ctx, reader_anchor_range(ctx, start), "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  errorf(ctx, reader_anchor_range(ctx, start), "LEB to large to even fit into a i128")
	}

	return
}

read_uXX_leb :: proc(ctx: ^Read_Ctx, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: u128(max(T))

	start := reader_anchor(ctx)

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
				errorf(ctx, reader_anchor_range(ctx, start), "LEB %[0]v has value to large to fit into a %[0]v: %v <= %v", typeid_of(T), value_u128, MAX)
			}
		} else {
			errorf(ctx, reader_anchor_range(ctx, start), "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: errorf(ctx, reader_anchor_range(ctx, start), "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  errorf(ctx, reader_anchor_range(ctx, start), "LEB to large to even fit into a u128")
	}

	return
}

read_u32_leb :: proc(ctx: ^Read_Ctx) -> (value: u32, ok: bool) { return read_uXX_leb(ctx, u32) }
read_i32_leb :: proc(ctx: ^Read_Ctx) -> (value: i32, ok: bool) { return read_iXX_leb(ctx, i32) }

read_u64_leb :: proc(ctx: ^Read_Ctx) -> (value: u64, ok: bool) { return read_uXX_leb(ctx, u64) }
read_i64_leb :: proc(ctx: ^Read_Ctx) -> (value: i64, ok: bool) { return read_iXX_leb(ctx, i64) }

read_validate_enum :: proc(ctx: ^Read_Ctx, anchor: int, input: byte, $T: typeid, $T_NAME: string) -> (value: T, ok: bool)  where intrinsics.type_is_enum(T), size_of(T) == size_of(byte) {
	if byte(min(T)) <= input && input <= byte(max(T)) {
		value = T(input)
		ok = true
	} else {
		errorf(ctx, reader_anchor_range(ctx, anchor), "invalid " + T_NAME + " %v: %v(0) <= %v(%v)", input, min(T), max(T), byte(max(T)))
	}

	return
}

read_byte_as_enum :: proc(ctx: ^Read_Ctx, $T: typeid, $T_NAME: string) -> (value: T, ok: bool) where intrinsics.type_is_enum(T), size_of(T) == size_of(byte) {
	anchor := reader_anchor(ctx)
	t_byte: u8
	t_byte, ok = read_byte(ctx)
	if ok {
		value, ok = read_validate_enum(ctx, anchor, t_byte, T, T_NAME)
	}

	return
}

as :: proc($T: typeid, a: $A, ok: bool) -> (T, bool) {
	return (T)(a), ok
}

read_vec :: proc(ctx: ^Read_Ctx, parse_proc: proc(ctx: ^Read_Ctx) -> ($T, bool), arena: ^B.Arena = nil) -> (data: []T, ok: bool) {
	arena := arena

	if arena == nil {
		arena = reader_arena(ctx)
	}

	size: u32
	size, ok = read_u32_leb(ctx)
	if ok {
		data = B.arena_push_make(arena, []T, size)

		for i in 0..<size {
			data[i], ok = parse_proc(ctx)
			if !ok {
				break
			}
		}
	}

	return
}

read_name :: proc(ctx: ^Read_Ctx) -> (s: string, ok: bool) {
	size: u32
	size, ok = read_u32_leb(ctx)
	if ok {
		bytes: []byte
		bytes, ok = read_bytes(ctx, int(size))
		s = string(bytes)
	}

	return
}

read_limits :: proc(ctx: ^Read_Ctx) -> (limits: Limits, ok: bool) {
	limits.kind, ok = read_byte_as_enum(ctx, Limits_Kind, "limits kind")
	if ok {
		limits.min, ok = read_u32_leb(ctx)
		if ok && limits.kind == .Limited {
			limits.max, ok = read_u32_leb(ctx)
		}
	}

	return
}

read_value_type :: proc(ctx: ^Read_Ctx) -> (value_type: Value_Type, ok: bool) {
	value_type, ok = read_byte_as_enum(ctx, Value_Type, "value type")
	return
}

read_func_type :: proc(ctx: ^Read_Ctx) -> (type: Function_Type, ok: bool) {
	start := reader_anchor(ctx)

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
				reader_anchor_range(ctx, start),
				"expected identifying byte for function, but got unknown one: %v != FUNCTION_TYPE_IDENTIFY_BYTE(%v)",
				identify_byte,
				FUNCTION_TYPE_IDENTIFY_BYTE,
			)
		}
	}

	return
}

read_element_type :: proc(ctx: ^Read_Ctx) -> (element_type: Element_Type, ok: bool) {
	anchor := reader_anchor(ctx)

	element_type_byte: byte
	element_type_byte, ok = read_byte(ctx)
	if ok {
		if element_type_byte == 0x70 /* The only valid element type for now */ {
			element_type = .Func_Ref
		} else {
			ok = false
			errorf(ctx, reader_anchor_range(ctx, anchor), "invalid element type, only support funcref(0x70) but got %h", element_type_byte)
		}
	}
	return
}

read_table_type :: proc(ctx: ^Read_Ctx) -> (table_type: Table_Type, ok: bool) {
	table_type.element_type, ok = read_element_type(ctx)
	if ok {
		table_type.limits, ok = read_limits(ctx)
	}

	return
}

read_global_type :: proc(ctx: ^Read_Ctx) -> (global_type: Global_Type, ok: bool) {
	global_type.type, ok = read_value_type(ctx)
	if ok {
		global_type.mutable, ok = read_t(ctx, b8)
	}

	return
}

read_import :: proc(ctx: ^Read_Ctx) -> (imp: Import, ok: bool) {
	imp.module, ok = read_name(ctx)
	if ok {
		imp.name, ok = read_name(ctx)
	}

	if ok {
		imp.kind, ok = read_byte_as_enum(ctx, External_Kind, "external kind")
	}

	if ok {
		switch imp.kind {
		case .Func:
			imp.type_index, ok = read_u32_leb(ctx)
		case .Table:
			imp.table_type, ok = read_table_type(ctx)
		case .Mem:
			imp.mem_type, ok = as(Memory, read_limits(ctx))
		case .Global:
			imp.global_type, ok = read_global_type(ctx)
		}
	}

	return
}

read_global :: proc(ctx: ^Read_Ctx) -> (global: Global, ok: bool) {
	global.type, ok = read_value_type(ctx)
	if ok {
		global.mutable, ok = read_t(ctx, b8)
		if ok {
			global.expr, ok = read_expr(ctx)
		}
	}
	return
}

read_export :: proc(ctx: ^Read_Ctx) -> (export: Export, ok: bool) {
	export.name, ok = read_name(ctx)
	if ok {
		export.kind, ok = read_byte_as_enum(ctx, External_Kind, "external kind")
		if ok {
			export.index, ok = read_u32_leb(ctx)
		}
	}
	return
}

read_element :: proc(ctx: ^Read_Ctx) -> (element: Element, ok: bool) {
	element.index, ok = read_u32_leb(ctx)
	if ok {
		element.expr, ok = read_expr(ctx)
	}

	if ok {
		element.init, ok = read_vec(ctx, read_u32_leb)
	}

	return
}

// Only reads the size of the code, not it's actual content
read_code_structure :: proc(ctx: ^Read_Ctx) -> (code: Bin_Code, ok: bool) {
	code.pos = reader_absolute_pos(ctx)
	size: int
	size, ok = as(int, read_u32_leb(ctx))
	if ok {
		code.data, ok = read_bytes(ctx, size)
	}

	return
}

read_data :: proc(ctx: ^Read_Ctx) -> (data: Data, ok: bool) {
	data.index, ok = read_u32_leb(ctx)
	if ok {
		data.expr, ok = read_expr(ctx)
	}

	if ok {
		init_count: u32
		init_count, ok = read_u32_leb(ctx)
		if ok {
			data.init, ok = read_bytes(ctx, int(init_count))
		}
	}

	return
}

read_type_section :: proc(ctx: ^Read_Ctx) -> (types: []Function_Type, ok: bool) {
	types, ok = read_vec(ctx, read_func_type)
	return
}

read_import_section :: proc(ctx: ^Read_Ctx) -> (imps: []Import, ok: bool) {
	imps, ok = read_vec(ctx, read_import)
	return
}

read_func_section :: proc(ctx: ^Read_Ctx) -> (funcs: []Type_Index, ok: bool) {
	funcs, ok = read_vec(ctx, proc(ctx: ^Read_Ctx) -> (type_index: Type_Index, ok: bool) { return as(Type_Index, read_u32_leb(ctx)) })
	return
}

read_table_section :: proc(ctx: ^Read_Ctx) -> (tables: []Table_Type, ok: bool) {
	tables, ok = read_vec(ctx, read_table_type)
	return
}

read_memory_section :: proc(ctx: ^Read_Ctx) -> (mems: []Memory, ok: bool) {
	mems, ok = read_vec(ctx, proc(ctx: ^Read_Ctx) -> (memory: Memory, ok: bool) { return as(Memory, read_limits(ctx)) })
	return
}

read_global_section :: proc(ctx: ^Read_Ctx) -> (globals: []Global, ok: bool) {
	globals, ok = read_vec(ctx, read_global)
	return
}

read_export_section :: proc(ctx: ^Read_Ctx) -> (exports: []Export, ok: bool) {
	exports, ok = read_vec(ctx, read_export)
	return
}

read_element_section :: proc(ctx: ^Read_Ctx) -> (elements: []Element, ok: bool) {
	elements, ok = read_vec(ctx, read_element)
	return
}

read_code_section_structure :: proc(ctx: ^Read_Ctx, arena: ^B.Arena) -> (codes: []Bin_Code, ok: bool) {
	codes, ok = read_vec(ctx, read_code_structure, arena)
	return
}

read_data_section :: proc(ctx: ^Read_Ctx) -> (datas: []Data, ok: bool) {
	datas, ok = read_vec(ctx, read_data)
	return
}

read_module :: proc(data: []byte, file: string) -> (ok: bool) {
	temp := B.TEMP_ALLOCATOR_GUARD()
	ctx  := B.arena_push(temp, Read_Ctx)

	ctx.data = data

	if B.lane_idx() == 0 {
		ctx.m        = B.arena_bootstrap_new(Bin_Module, "arena")
		ctx.m.arenas = B.arena_push_make(ctx.m.arena, []^B.Arena, B.lane_count())
	}

	B.lane_sync_value(&ctx.m, 0)

	ctx.m.arenas[B.lane_idx()] = B.arena_alloc(commited = runtime.Kilobyte * 2)

	code_section_index := -1

	if B.lane_idx() == 0 {
		T.ZoneN("Read Module Header")

		anchor := reader_anchor(ctx)

		// read magic number
		magic: u32
		magic, ok = read_u32(ctx)
		if ok {
			if magic == BIN_MAGIC {
				ok = true
			} else {
				ok = false
				errorf(ctx, reader_anchor_range(ctx, anchor), "invalid magic number %v, expected %v", magic, BIN_MAGIC)
			}
		}

		anchor = reader_anchor(ctx)

		// read version number
		if ok {
			ctx.m.version, ok = read_u32(ctx)
			if ctx.m.version == BIN_SUPPORTED_VERSION {
				ok = true
			} else {
				ok = false
				errorf(ctx, reader_anchor_range(ctx, anchor), "unsupported WASM version %v, currently only WASM 1.0 is supported", ctx.m.version)
			}
		}

		// fast-collect all sections for parallel processing
		section_list: Section_List
		if ok {
			for ctx.curr < len(ctx.data) {
				start := reader_anchor(ctx)

				section := Bin_Section{
					pos = ctx.curr,
				}

				section.kind, ok = read_t(ctx, Bin_Section_Kind)
				if !ok {
					break
				}

				ok = u8(section.kind) <= u8(max(Bin_Section_Kind))
				if !ok {
					errorf(ctx, reader_anchor_range(ctx, start), "invalid section kind %d, expected 0..=%v", u8(section.kind), u8(max(Bin_Section_Kind)))
					break
				}

				size: int
				size, ok = as(int, read_u32_leb(ctx))
				if !ok {
					break
				}

				section.data, ok = read_bytes(ctx, size)
				if !ok {
					break
				}

				node         := B.arena_push(ctx.m.arena, Bin_Section_Node)
				node.section  = section
				list_push(&section_list, node)
			}
		}

		// collect all sections into a linear array
		if ok {
			ctx.m.sections = B.arena_push_make(ctx.m.arena, []Bin_Section, section_list.count)

			i := 0
			for current := section_list.first; current != nil; current = current.next {
				ctx.m.sections[i] = current.section

				if current.section.kind == .Code {
					code_section_index = i
				}

				i += 1
			}
		}
	}

	B.lane_sync_value(&ok, 0)

	if !ok {
		return
	}

	B.lane_sync_value(&code_section_index, 0)

	m := ctx.m

	section_rng := B.lane_range(len(m.sections))
	for i in section_rng.start..<section_rng.end {
		T.ZoneN("Read Section")

		section := m.sections[i]
		defer m.sections[i] = section

		reader_set_scope(ctx, section.pos, section.data)

		// we do not care about ok==false, because we will not handle ok but instead look at the diagnostic list
		switch section.kind {
		case .Custom: // do nothing
		case .Type:     section.types,     _ = read_type_section(ctx)
		case .Import:   section.imps,      _ = read_import_section(ctx)
		case .Function: section.functions, _ = read_func_section(ctx)
		case .Table:    section.tables,    _ = read_table_section(ctx)
		case .Memory:   section.memory,    _ = read_memory_section(ctx)
		case .Global:   section.globals,   _ = read_global_section(ctx)
		case .Export:   section.exports,   _ = read_export_section(ctx)
		case .Start:    section.start,     _ = read_u32_leb(ctx)
		case .Element:  section.elements,  _ = read_element_section(ctx)
		case .Code:     section.codes,     _ = read_code_section_structure(ctx)
		case .Data:     section.datas,     _ = read_data_section(ctx)
		}
	}

	B.lane_sync()

	if 0 <= code_section_index {
		code_section := &ctx.m.sections[code_section_index]
		code_rng     := B.lane_range(len(code_section.codes))
		for i in code_rng.start..<code_rng.end {
			code := code_section.codes[i]
			reader_set_scope(ctx, code.pos, code.data)

			code.locals, ok = read_vec(
				ctx,
				proc(ctx: ^Read_Ctx) -> (local: Local, ok: bool) {
					local.repeat = read_u32_leb(ctx) or_return
					local.type   = read_value_type(ctx) or_return
					ok = true
					return
				},
			)

			if ok {
				code.expr, _ = read_expr(ctx)
			}

			code_section.codes[i] = code
		}
	}

	B.lane_sync()

	ctxs: []^Read_Ctx

	if B.lane_idx() == 0 {
		ctxs = B.arena_push_make(temp, []^Read_Ctx, B.lane_count())
	}

	ctxs_ptr: [^]^Read_Ctx = raw_data(ctxs)
	B.lane_sync_value(&ctxs_ptr, 0)

	ctxs_ptr[B.lane_idx()] = ctx

	B.lane_sync()

	if B.lane_idx() == 0 {
		all_diags_count := 0

		for lane_ctx in ctxs {
			all_diags_count += lane_ctx.digs.count
		}

		all_diags := B.arena_push_slice(temp, []Diagnostic, all_diags_count)

		offset := 0
		if 0 < all_diags_count {
			for lane_ctx in ctxs {
				for current := lane_ctx.digs.first; current != nil; current = current.next {
					all_diags[offset] = current.diag
					offset += 1
				}
			}
		}

		if 0 < all_diags_count {
			fmt.eprintfln("malformed module, found %v errors:", all_diags_count)
			for diag in all_diags {
				fmt.eprintfln("%v:%v-%v:Error: %v", file, diag.range.start, diag.range.end, diag.error)
			}
		}

		fmt.printfln("found module with version %v", m.version)
		for section in m.sections {
			fmt.printfln("found section of type %q: %v", section.kind, section)
		}
	}

	B.lane_sync()

	return
}

bin_scan_module :: proc(ctx: ^Read_Ctx) -> (m: ^Bin_Module, ok: bool) {
	m = B.arena_push(ctx.arena, Bin_Module)

	T.ZoneN("Read Module Header")

	anchor := reader_anchor(ctx)

	magic: u32
	magic, ok = read_u32(ctx)
	if ok {
		if magic != BIN_MAGIC {
			ok = false
			errorf(ctx, reader_anchor_range(ctx, anchor), "invalid magic number %v, expected %v", magic, BIN_MAGIC)
		}
	}

	anchor = reader_anchor(ctx)

	if ok {
		m.version, ok = read_u32(ctx)
		if m.version != BIN_SUPPORTED_VERSION {
			ok = false
			errorf(ctx, reader_anchor_range(ctx, anchor), "unsupported WASM version %v, currently only WASM 1.0 is supported", m.version)
		}
	}


	// fast-collect all sections for parallel processing
	section_list: Section_List
	if ok {
		for ctx.curr < len(ctx.data) {
			start := reader_anchor(ctx)

			section := Bin_Section{
				pos = ctx.curr,
			}

			section.kind, ok = read_t(ctx, Bin_Section_Kind)
			if !ok {
				break
			}

			ok = u8(section.kind) <= u8(max(Bin_Section_Kind))
			if !ok {
				errorf(ctx, reader_anchor_range(ctx, start), "invalid section kind %d, expected 0..=%v", u8(section.kind), u8(max(Bin_Section_Kind)))
				break
			}

			size: int
			size, ok = as(int, read_u32_leb(ctx))
			if !ok {
				break
			}

			section.data, ok = read_bytes(ctx, size)
			if !ok {
				break
			}

			node         := B.arena_push(ctx.arena, Bin_Section_Node)
			node.section  = section
			list_push(&section_list, node)
		}
	}

	// collect all sections into a linear array
	if ok {
		m.sections = B.arena_push_make(ctx.arena, []Bin_Section, section_list.count)

		i := 0
		for current := section_list.first; current != nil; current = current.next {
			m.sections[i] = current.section

			if current.section.kind == .Code {
				m.code_section_index = i
			}

			i += 1
		}
	}

	return
}

bin_read_section_into_module :: proc(ctx: ^Read_Ctx, section: Bin_Section, m: ^Module) -> (ok: bool) {
	ok = true

	reader_set_scope(ctx, section.pos, section.data)

	switch section.kind {
	case .Custom: // do nothing
	case .Type:     m.types,     ok = read_type_section(ctx)
	case .Import:   m.imps,      ok = read_import_section(ctx)
	case .Function: m.functions, ok = read_func_section(ctx)
	case .Table:    m.tables,    ok = read_table_section(ctx)
	case .Memory:   m.memory,    ok = read_memory_section(ctx)
	case .Global:   m.globals,   ok = read_global_section(ctx)
	case .Export:   m.exports,   ok = read_export_section(ctx)
	case .Start:    m.start,     ok = read_u32_leb(ctx)
	case .Element:  m.elements,  ok = read_element_section(ctx)
	case .Data:     m.datas,     ok = read_data_section(ctx)

	// TODO(robin): still not happy with this, makes the interface very ugly
	case .Code: panic(#procedure + ": a code section is treated specially for performance reasons, you should special case it and call read_code_section_structure instead")
	}

	return
}

bin_read_code :: proc(ctx: ^Read_Ctx, bin_code: Bin_Code) -> (code: Code, ok: bool) {
	reader_set_scope()
}

Thread_Data :: struct {
	lane_ctx: B.Lane_Ctx,
	thread: ^thread.Thread,
	data: []byte,
	file: string,
	ctx: Read_Ctx,
	module: ^Module,
	done: ^sync.One_Shot_Event,
}

read_entry_point : thread.Thread_Proc : proc(t: ^thread.Thread) {
	tdata := (^Thread_Data)(t.data)

	B.lane_select_ctx(tdata.lane_ctx)

	temp := B.TEMP_ALLOCATOR_GUARD()
	T.SetThreadName(strings.clone_to_cstring(t.name.?, allocator = temp) if t.name != nil else "")

	B.lane_sync()

	read_module(tdata.data, tdata.file)

	if B.lane_idx() == 0 {
		sync.one_shot_event_signal(tdata.done)
	}
}

@private
bin_read_entry_point : thread.Thread_Proc : proc(t: ^thread.Thread) {
	tdata := (^Thread_Data)(t.data)
	defer if B.lane_idx() == 0 {
		sync.one_shot_event_signal(tdata.done)
	}

	B.lane_select_ctx(tdata.lane_ctx)

	temp := B.TEMP_ALLOCATOR_GUARD()
	T.SetThreadName(strings.clone_to_cstring(t.name.?, allocator = temp) if t.name != nil else "")

	B.lane_sync()

	ctx := &tdata.ctx

	bin_module: ^Bin_Module

	ok: bool
	if B.lane_idx() == 0 {
		bin_module, ok = bin_scan_module(ctx)
	}

	B.lane_sync_value(&ok, 0)

	if !ok {
		return
	}

	B.lane_sync_value(&bin_module, 0)

	section_rng := B.lane_range(len(bin_module.sections))
	for i in section_rng.start..<section_rng.end {
		bin_read_section_into_module(ctx, bin_module.sections[i], tdata.module)
	}

	B.lane_sync()

	if 0 <= bin_module.code_section_index {
		code_section := bin_module.sections[bin_module.code_section_index]

		reader_set_scope(ctx, code_section.pos, code_section.data)

		bin_codes: []Bin_Code

		if B.lane_idx() == 0 {
			bin_codes, ok = read_code_section_structure(ctx, temp)

			if ok {
				tdata.module.codes = B.arena_push_make(ctx.arena, []Code, len(bin_codes))
			}
		}

		B.lane_sync_value(&ok, 0)

		if ok {
			B.lane_sync_value(&bin_codes, 0)

			bin_code_rng := B.lane_range(len(bin_codes))
			for i in bin_code_rng.start..<bin_code_rng.end {
				bin_code := bin_codes[i]
				reader_set_scope(ctx, bin_code.pos, bin_code.data)

				code: Code
				defer tdata.module.codes[i] = code

				code.locals, ok = read_vec(
					ctx,
					proc(ctx: ^Read_Ctx) -> (local: Local, ok: bool) {
						local.repeat = read_u32_leb(ctx) or_return
						local.type   = read_value_type(ctx) or_return
						ok = true
						return
					},
				)

				if ok {
					code.expr, _ = read_expr(ctx)
				}
			}
		}
	}

	B.lane_sync()
}

bin_read :: proc(data: []byte, file_name: string, thread_arenas: []^B.Arena) -> (module: Module, diags: []Diagnostic) {
	assert(0 < len(thread_arenas))

	temp := B.TEMP_ALLOCATOR_GUARD()

	thread_count := len(thread_arenas)

	lane_shared_memory: u128
	barrier: sync.Barrier
	done_one_shot_event: sync.One_Shot_Event
	sync.barrier_init(&barrier, thread_count)
	per_thread_tdata := B.arena_push_make(temp, []Thread_Data, thread_count)

	for &tdata, i in per_thread_tdata {
		tdata.lane_ctx.index = i
		tdata.lane_ctx.count = thread_count
		tdata.lane_ctx.barrier = &barrier
		tdata.lane_ctx.shared_memory = &lane_shared_memory

		tdata.module = &module
		tdata.done = &done_one_shot_event
		tdata.data = data
		tdata.file = file_name

		tdata.ctx = {
			data  = data,
			arena = thread_arenas[i],
		}

		tdata.thread = thread.create(read_entry_point, name = fmt.aprintf("wasim_%v", i, allocator = temp))
		tdata.thread.data = &tdata
	}

	for tdata in per_thread_tdata {
		thread.start(tdata.thread)
	}

	sync.one_shot_event_wait(&done_one_shot_event)

	for tdata in per_thread_tdata {
		thread.join(tdata.thread)
	}

	return
}

main :: proc() {
	B.inst_begin_profile()
	defer B.inst_end_profile()

	Cmd :: struct {
		input_module: ^os.File `args:"pos=0,required"`,
		thread_count: int,
	}

	cmd: Cmd

	flags.parse_or_exit(&cmd, os.args, allocator = context.temp_allocator)

	data, err := os.read_entire_file(cmd.input_module, context.temp_allocator)
	if err == nil {
		T.ZoneN("Init")

		temp := B.TEMP_ALLOCATOR_GUARD()

		thread_count: int
		if cmd.thread_count == 0 {
			// try to infer virtual core count
			physical_core_count, virtual_core_count, _ := info.cpu_core_count()
			thread_count = virtual_core_count if virtual_core_count != 0 else physical_core_count
		}

		thread_count = max(1, thread_count)


		lane_shared_memory: u64
		barrier: sync.Barrier
		done_one_shot_event: sync.One_Shot_Event
		sync.barrier_init(&barrier, thread_count)
		per_thread_tdata := B.arena_push_make(temp, []Thread_Data, thread_count)

		for &tdata, i in per_thread_tdata {
			tdata.lane_ctx.index = i
			tdata.lane_ctx.count = thread_count
			tdata.lane_ctx.barrier = &barrier
			tdata.lane_ctx.shared_memory = &lane_shared_memory

			tdata.done = &done_one_shot_event

			tdata.data = data
			tdata.file = os.name(cmd.input_module)

			tdata.thread = thread.create(read_entry_point, name = fmt.aprintf("wasim_%v", i, allocator = temp))
			tdata.thread.data = &tdata
		}

		for tdata in per_thread_tdata {
			thread.start(tdata.thread)
		}

		sync.one_shot_event_wait(&done_one_shot_event)

		for tdata in per_thread_tdata {
			thread.join(tdata.thread)
		}
	} else {
		fmt.eprintfln("could not read file %q: %v", os.name(cmd.input_module), err)
	}
}
