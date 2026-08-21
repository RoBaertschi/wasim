package wasim

import "core:slice"
import "core:fmt"
import "core:sync"
import "core:thread"
import "core:strings"
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

Bin_Read_Ctx :: struct {
	base:  int,    // base offset into file
	curr:  int,    // current offset into data
	data:  []byte, // slice inside file (does not need to be the whole file)
	diags: Diagnostic_List,

	arena: ^B.Arena,
}

bin_reader_set_scope :: proc(ctx: ^Bin_Read_Ctx, base: int, data: []byte) {
	ctx.base = base
	ctx.curr = 0
	ctx.data = data
}

bin_reader_push_data :: proc(ctx: ^Bin_Read_Ctx, count: int) -> (old_base, resume_curr: int, old_data: []byte, ok: bool) {
	start     := bin_reader_anchor(ctx)
	data_left := bin_reader_data_left(ctx)

	if count < 0 || data_left < count {
		bin_errorf(ctx, B.rng1(start, start+data_left), "missing %v bytes", count-data_left)
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

bin_reader_pop_data :: proc(ctx: ^Bin_Read_Ctx, old_base, resume_curr: int, old_data: []byte) {
	ctx.base = old_base
	ctx.curr = resume_curr
	ctx.data = old_data
}

_bin_reader_end_data :: proc(ctx: ^Bin_Read_Ctx, _: int, old_base, resume_curr: int, old_data: []byte, ok: bool) {
	if ok {
		bin_reader_pop_data(ctx, old_base, resume_curr, old_data)
	}
}

@(deferred_in_out=_bin_reader_end_data)
bin_reader_data_guard :: proc(ctx: ^Bin_Read_Ctx, count: int) -> (old_base, resume_curr: int, old_data: []byte, ok: bool) {
	return bin_reader_push_data(ctx, count)
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


Bin_Section_List :: List(Bin_Section_Node)

Bin_Module :: struct {
	version: u32,
	sections: []Bin_Section,
	code_section_index: int,
}

bin_reader_arena :: proc(ctx: ^Bin_Read_Ctx) -> ^B.Arena {
	return ctx.arena
}

bin_reader_allocator :: proc(ctx: ^Bin_Read_Ctx) -> runtime.Allocator {
	return B.arena_allocator(bin_reader_arena(ctx))
}

bin_errorf :: proc(ctx: ^Bin_Read_Ctx, range: Byte_Range, format: string, args: ..any) {
	diag := Diagnostic {
		error = fmt.aprintf(format, ..args, allocator = bin_reader_allocator(ctx)),
		range = range,
	}

	diag_list_push(bin_reader_arena(ctx), &ctx.diags, diag)
}

bin_reader_absolute_pos :: proc(ctx: ^Bin_Read_Ctx) -> int {
	return ctx.base + ctx.curr
}

bin_reader_anchor :: bin_reader_absolute_pos

bin_reader_anchor_range :: proc(ctx: ^Bin_Read_Ctx, anchor: int) -> (result: Byte_Range) {
	result.start = anchor
	result.end   = bin_reader_anchor(ctx)
	assert(result.start <= result.end)
	return
}

bin_reader_data_left :: proc(ctx: ^Bin_Read_Ctx) -> int {
	return len(ctx.data) - ctx.curr
}

bin_read_bytes :: proc(ctx: ^Bin_Read_Ctx, count: int) -> (bytes: []byte, ok: bool) {
	start     := bin_reader_anchor(ctx)
	data_left := bin_reader_data_left(ctx)

	if count <= data_left {
		pos   := ctx.curr
		bytes  = ctx.data[pos:pos+count]
		ok     = true

		ctx.curr += count
	} else {
		bin_errorf(ctx, B.rng1(start, start+data_left), "missing %v bytes", count-data_left)
	}

	return
}

bin_read_t :: proc(ctx: ^Bin_Read_Ctx, $T: typeid) -> (value: T, ok: bool) {
	data: []byte
	data, ok = bin_read_bytes(ctx, size_of(T))

	if ok {
		value = (^T)(raw_data(data))^
	}

	return
}

bin_read_u32 :: proc(ctx: ^Bin_Read_Ctx) -> (u32, bool) { return bin_read_t(ctx, u32) }
bin_read_u64 :: proc(ctx: ^Bin_Read_Ctx) -> (u64, bool) { return bin_read_t(ctx, u64) }

bin_read_byte :: proc(ctx: ^Bin_Read_Ctx) -> (result: u8, ok: bool) {
	start := bin_reader_anchor(ctx)

	if 1 <= bin_reader_data_left(ctx) {
		result    = ctx.data[ctx.curr]
		ok        = true
		ctx.curr += 1
	} else {
		bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "missing byte")
	}

	return
}

bin_read_iXX_leb :: proc(ctx: ^Bin_Read_Ctx, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), !intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: i128(max(T))
	MIN       :: i128(min(T))

	start := bin_reader_anchor(ctx)

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
				bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "LEB %[0]v has value that does not fit into a %[0]v: MIN(%v) <= %v <= MAX(%v)", typeid_of(T), MIN, value_i128, MAX)
			}
		} else {
			bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "LEB to large to even fit into a i128")
	}

	return
}

bin_read_uXX_leb :: proc(ctx: ^Bin_Read_Ctx, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: u128(max(T))

	start := bin_reader_anchor(ctx)

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
				bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "LEB %[0]v has value to large to fit into a %[0]v: %v <= %v", typeid_of(T), value_u128, MAX)
			}
		} else {
			bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "LEB to large to even fit into a u128")
	}

	return
}

bin_read_u32_leb :: proc(ctx: ^Bin_Read_Ctx) -> (value: u32, ok: bool) { return bin_read_uXX_leb(ctx, u32) }
bin_read_i32_leb :: proc(ctx: ^Bin_Read_Ctx) -> (value: i32, ok: bool) { return bin_read_iXX_leb(ctx, i32) }

bin_read_u64_leb :: proc(ctx: ^Bin_Read_Ctx) -> (value: u64, ok: bool) { return bin_read_uXX_leb(ctx, u64) }
bin_read_i64_leb :: proc(ctx: ^Bin_Read_Ctx) -> (value: i64, ok: bool) { return bin_read_iXX_leb(ctx, i64) }

bin_read_validate_enum :: proc(ctx: ^Bin_Read_Ctx, anchor: int, input: byte, $T: typeid, $T_NAME: string) -> (value: T, ok: bool)  where intrinsics.type_is_enum(T), size_of(T) == size_of(byte) {
	if byte(min(T)) <= input && input <= byte(max(T)) {
		value = T(input)
		ok = true
	} else {
		bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "invalid " + T_NAME + " %v: %v(0) <= %v(%v)", input, min(T), max(T), byte(max(T)))
	}

	return
}

bin_read_byte_as_enum :: proc(ctx: ^Bin_Read_Ctx, $T: typeid, $T_NAME: string) -> (value: T, ok: bool) where intrinsics.type_is_enum(T), size_of(T) == size_of(byte) {
	anchor := bin_reader_anchor(ctx)
	t_byte: u8
	t_byte, ok = bin_read_byte(ctx)
	if ok {
		value, ok = bin_read_validate_enum(ctx, anchor, t_byte, T, T_NAME)
	}

	return
}

bin_as :: proc($T: typeid, a: $A, ok: bool) -> (T, bool) {
	return (T)(a), ok
}

bin_read_vec :: proc(ctx: ^Bin_Read_Ctx, parse_proc: proc(ctx: ^Bin_Read_Ctx) -> ($T, bool), arena: ^B.Arena = nil) -> (data: []T, ok: bool) {
	arena := arena

	if arena == nil {
		arena = bin_reader_arena(ctx)
	}

	size: u32
	size, ok = bin_read_u32_leb(ctx)
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

bin_read_name :: proc(ctx: ^Bin_Read_Ctx) -> (s: string, ok: bool) {
	size: u32
	size, ok = bin_read_u32_leb(ctx)
	if ok {
		bytes: []byte
		bytes, ok = bin_read_bytes(ctx, int(size))
		s = string(bytes)
	}

	return
}

bin_read_limits :: proc(ctx: ^Bin_Read_Ctx) -> (limits: Limits, ok: bool) {
	limits.kind, ok = bin_read_byte_as_enum(ctx, Limits_Kind, "limits kind")
	if ok {
		limits.min, ok = bin_read_u32_leb(ctx)
		if ok && limits.kind == .Limited {
			limits.max, ok = bin_read_u32_leb(ctx)
		}
	}

	return
}

bin_read_value_type :: proc(ctx: ^Bin_Read_Ctx) -> (value_type: Value_Type, ok: bool) {
	value_type, ok = bin_read_byte_as_enum(ctx, Value_Type, "value type")
	return
}

bin_read_func_type :: proc(ctx: ^Bin_Read_Ctx) -> (type: Function_Type, ok: bool) {
	start := bin_reader_anchor(ctx)

	identify_byte: byte
	identify_byte, ok = bin_read_byte(ctx)
	if ok {
		FUNCTION_TYPE_IDENTIFY_BYTE :: 0x60

		if identify_byte == FUNCTION_TYPE_IDENTIFY_BYTE {
			type.args, ok = bin_read_vec(ctx, bin_read_value_type)
			if ok {
				type.rets, ok = bin_read_vec(ctx, bin_read_value_type)
			}
		} else {
			ok = false
			bin_errorf(
				ctx,
				bin_reader_anchor_range(ctx, start),
				"expected identifying byte for function, but got unknown one: %v != FUNCTION_TYPE_IDENTIFY_BYTE(%v)",
				identify_byte,
				FUNCTION_TYPE_IDENTIFY_BYTE,
			)
		}
	}

	return
}

bin_read_element_type :: proc(ctx: ^Bin_Read_Ctx) -> (element_type: Element_Type, ok: bool) {
	anchor := bin_reader_anchor(ctx)

	element_type_byte: byte
	element_type_byte, ok = bin_read_byte(ctx)
	if ok {
		if element_type_byte == 0x70 /* The only valid element type for now */ {
			element_type = .Func_Ref
		} else {
			ok = false
			bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "invalid element type, only support funcref(0x70) but got %h", element_type_byte)
		}
	}
	return
}

bin_read_table_type :: proc(ctx: ^Bin_Read_Ctx) -> (table_type: Table_Type, ok: bool) {
	table_type.element_type, ok = bin_read_element_type(ctx)
	if ok {
		table_type.limits, ok = bin_read_limits(ctx)
	}

	return
}

bin_read_global_type :: proc(ctx: ^Bin_Read_Ctx) -> (global_type: Global_Type, ok: bool) {
	global_type.type, ok = bin_read_value_type(ctx)
	if ok {
		global_type.mutable, ok = bin_read_t(ctx, b8)
	}

	return
}

bin_read_import :: proc(ctx: ^Bin_Read_Ctx) -> (imp: Import, ok: bool) {
	imp.module, ok = bin_read_name(ctx)
	if ok {
		imp.name, ok = bin_read_name(ctx)
	}

	if ok {
		imp.kind, ok = bin_read_byte_as_enum(ctx, External_Kind, "external kind")
	}

	if ok {
		switch imp.kind {
		case .Func:
			imp.type_index, ok = bin_read_u32_leb(ctx)
		case .Table:
			imp.table_type, ok = bin_read_table_type(ctx)
		case .Mem:
			imp.mem_type, ok = bin_as(Memory, bin_read_limits(ctx))
		case .Global:
			imp.global_type, ok = bin_read_global_type(ctx)
		}
	}

	return
}

bin_read_global :: proc(ctx: ^Bin_Read_Ctx) -> (global: Global, ok: bool) {
	global.type, ok = bin_read_value_type(ctx)
	if ok {
		global.mutable, ok = bin_read_t(ctx, b8)
		if ok {
			global.expr, ok = bin_read_expr(ctx)
		}
	}
	return
}

bin_read_export :: proc(ctx: ^Bin_Read_Ctx) -> (export: Export, ok: bool) {
	export.name, ok = bin_read_name(ctx)
	if ok {
		export.kind, ok = bin_read_byte_as_enum(ctx, External_Kind, "external kind")
		if ok {
			export.index, ok = bin_read_u32_leb(ctx)
		}
	}
	return
}

bin_read_element :: proc(ctx: ^Bin_Read_Ctx) -> (element: Element, ok: bool) {
	element.index, ok = bin_read_u32_leb(ctx)
	if ok {
		element.expr, ok = bin_read_expr(ctx)
	}

	if ok {
		element.init, ok = bin_read_vec(ctx, bin_read_u32_leb)
	}

	return
}

// Only reads the size of the code, not it's actual content
bin_read_code_structure :: proc(ctx: ^Bin_Read_Ctx) -> (code: Bin_Code, ok: bool) {
	code.pos = bin_reader_absolute_pos(ctx)
	size: int
	size, ok = bin_as(int, bin_read_u32_leb(ctx))
	if ok {
		code.data, ok = bin_read_bytes(ctx, size)
	}

	return
}

bin_read_data :: proc(ctx: ^Bin_Read_Ctx) -> (data: Data, ok: bool) {
	data.index, ok = bin_read_u32_leb(ctx)
	if ok {
		data.expr, ok = bin_read_expr(ctx)
	}

	if ok {
		init_count: u32
		init_count, ok = bin_read_u32_leb(ctx)
		if ok {
			data.init, ok = bin_read_bytes(ctx, int(init_count))
		}
	}

	return
}

bin_read_type_section :: proc(ctx: ^Bin_Read_Ctx) -> (types: []Function_Type, ok: bool) {
	types, ok = bin_read_vec(ctx, bin_read_func_type)
	return
}

bin_read_import_section :: proc(ctx: ^Bin_Read_Ctx) -> (imps: []Import, ok: bool) {
	imps, ok = bin_read_vec(ctx, bin_read_import)
	return
}

bin_read_func_section :: proc(ctx: ^Bin_Read_Ctx) -> (funcs: []Type_Index, ok: bool) {
	funcs, ok = bin_read_vec(ctx, proc(ctx: ^Bin_Read_Ctx) -> (type_index: Type_Index, ok: bool) { return bin_as(Type_Index, bin_read_u32_leb(ctx)) })
	return
}

bin_read_table_section :: proc(ctx: ^Bin_Read_Ctx) -> (tables: []Table_Type, ok: bool) {
	tables, ok = bin_read_vec(ctx, bin_read_table_type)
	return
}

bin_read_memory_section :: proc(ctx: ^Bin_Read_Ctx) -> (mems: []Memory, ok: bool) {
	mems, ok = bin_read_vec(ctx, proc(ctx: ^Bin_Read_Ctx) -> (memory: Memory, ok: bool) { return bin_as(Memory, bin_read_limits(ctx)) })
	return
}

bin_read_global_section :: proc(ctx: ^Bin_Read_Ctx) -> (globals: []Global, ok: bool) {
	globals, ok = bin_read_vec(ctx, bin_read_global)
	return
}

bin_read_export_section :: proc(ctx: ^Bin_Read_Ctx) -> (exports: []Export, ok: bool) {
	exports, ok = bin_read_vec(ctx, bin_read_export)
	return
}

bin_read_element_section :: proc(ctx: ^Bin_Read_Ctx) -> (elements: []Element, ok: bool) {
	elements, ok = bin_read_vec(ctx, bin_read_element)
	return
}

bin_read_code_section_structure :: proc(ctx: ^Bin_Read_Ctx, arena: ^B.Arena) -> (codes: []Bin_Code, ok: bool) {
	codes, ok = bin_read_vec(ctx, bin_read_code_structure, arena)
	return
}

bin_read_data_section :: proc(ctx: ^Bin_Read_Ctx) -> (datas: []Data, ok: bool) {
	datas, ok = bin_read_vec(ctx, bin_read_data)
	return
}

bin_scan_module :: proc(ctx: ^Bin_Read_Ctx) -> (m: ^Bin_Module, ok: bool) {
	m = B.arena_push(ctx.arena, Bin_Module)
	m.code_section_index = -1

	T.ZoneN("Read Module Header")

	anchor := bin_reader_anchor(ctx)

	magic: u32
	magic, ok = bin_read_u32(ctx)
	if ok {
		if magic != BIN_MAGIC {
			ok = false
			bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "invalid magic number %v, expected %v", magic, BIN_MAGIC)
		}
	}

	anchor = bin_reader_anchor(ctx)

	if ok {
		m.version, ok = bin_read_u32(ctx)
		if m.version != BIN_SUPPORTED_VERSION {
			ok = false
			bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "unsupported WASM version %v, currently only WASM 1.0 is supported", m.version)
		}
	}


	// fast-collect all sections for parallel processing
	section_list: Bin_Section_List
	if ok {
		for ctx.curr < len(ctx.data) {
			start := bin_reader_anchor(ctx)

			section := Bin_Section{
				pos = ctx.curr,
			}

			section.kind, ok = bin_read_t(ctx, Bin_Section_Kind)
			if !ok {
				break
			}

			ok = u8(section.kind) <= u8(max(Bin_Section_Kind))
			if !ok {
				bin_errorf(ctx, bin_reader_anchor_range(ctx, start), "invalid section kind %d, expected 0..=%v", u8(section.kind), u8(max(Bin_Section_Kind)))
				break
			}

			size: int
			size, ok = bin_as(int, bin_read_u32_leb(ctx))
			if !ok {
				break
			}

			section.data, ok = bin_read_bytes(ctx, size)
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

bin_read_section_into_module :: proc(ctx: ^Bin_Read_Ctx, section: Bin_Section, m: ^Module) -> (ok: bool) {
	ok = true

	bin_reader_set_scope(ctx, section.pos, section.data)

	switch section.kind {
	case .Custom: // do nothing
	case .Type:     m.types,     ok = bin_read_type_section(ctx)
	case .Import:   m.imps,      ok = bin_read_import_section(ctx)
	case .Function: m.functions, ok = bin_read_func_section(ctx)
	case .Table:    m.tables,    ok = bin_read_table_section(ctx)
	case .Memory:   m.memory,    ok = bin_read_memory_section(ctx)
	case .Global:   m.globals,   ok = bin_read_global_section(ctx)
	case .Export:   m.exports,   ok = bin_read_export_section(ctx)
	case .Start:    m.start,     ok = bin_read_u32_leb(ctx)
	case .Element:  m.elements,  ok = bin_read_element_section(ctx)
	case .Data:     m.datas,     ok = bin_read_data_section(ctx)

	// TODO(robin): still not happy with this, makes the interface very ugly
	case .Code: panic(#procedure + ": a code section is treated specially for performance reasons, you should special case it and call bin_read_code_section_structure instead")
	}

	return
}

bin_read_code :: proc(ctx: ^Bin_Read_Ctx, bin_code: Bin_Code) -> (code: Code, ok: bool) {
	bin_reader_set_scope(ctx, bin_code.pos, bin_code.data)

	code.locals, ok = bin_read_vec(
		ctx,
		proc(ctx: ^Bin_Read_Ctx) -> (local: Local, ok: bool) {
			local.repeat = bin_read_u32_leb(ctx) or_return
			local.type   = bin_read_value_type(ctx) or_return
			ok = true
			return
		},
	)

	if ok {
		code.expr, ok = bin_read_expr(ctx)
	}

	return
}

bin_collect_diagnostics :: proc(arena: ^B.Arena, ctxs: []Bin_Read_Ctx) -> (diags: []Diagnostic) {
	diags_count := slice.reduce(ctxs, 0, proc(sum: int, ctx: Bin_Read_Ctx) -> int { return sum + ctx.diags.count })

	diags = B.arena_push_make(arena, []Diagnostic, diags_count)

	i: int
	for ctx in ctxs {
		for current := ctx.diags.first; current != nil; current = current.next {
			diags[i]  = current.diag
			i        += 1
		}
	}

	return
}

Bin_Thread_Data :: struct {
	lane_ctx: B.Lane_Ctx,
	thread: ^thread.Thread,
	data: []byte,
	file: string,
	module: ^Module,
	diags: ^[]Diagnostic,
	arenas: []^B.Arena,
	done: ^sync.One_Shot_Event,
}

@private
bin_read_entry_point : thread.Thread_Proc : proc(t: ^thread.Thread) {
	tdata := (^Bin_Thread_Data)(t.data)
	defer if B.lane_idx() == 0 {
		sync.one_shot_event_signal(tdata.done)
	}

	B.lane_select_ctx(tdata.lane_ctx)

	lane := B.lane_idx()

	temp := B.TEMP_ALLOCATOR_GUARD()
	T.SetThreadName(strings.clone_to_cstring(t.name.?, allocator = temp) if t.name != nil else "")

	B.lane_sync()
	
	ctxs: []Bin_Read_Ctx

	if lane == 0 {
		ctxs = B.arena_push_make(temp, []Bin_Read_Ctx, B.lane_count())
	}

	B.lane_sync_value(&ctxs, 0)

	ctxs[lane].arena = tdata.arenas[lane]

	ctx := &ctxs[lane]

	bin_module: ^Bin_Module

	ok: bool
	if lane == 0 {
		bin_reader_set_scope(ctx, 0, tdata.data)
		bin_module, ok = bin_scan_module(ctx)
		tdata.module.version = bin_module.version
	}

	B.lane_sync_value(&ok, 0)

	if !ok {
		return
	}

	B.lane_sync_value(&bin_module, 0)

	for bin_section in B.lane_range_slice(bin_module.sections) {
		if bin_section.kind != .Code {
			_ = bin_read_section_into_module(ctx, bin_section, tdata.module)
		}
	}

	B.lane_sync()

	if 0 <= bin_module.code_section_index {
		code_section := bin_module.sections[bin_module.code_section_index]

		bin_reader_set_scope(ctx, code_section.pos, code_section.data)

		bin_codes: []Bin_Code

		if lane == 0 {
			bin_codes, ok = bin_read_code_section_structure(ctx, temp)

			if ok {
				tdata.module.codes = B.arena_push_make(ctx.arena, []Code, len(bin_codes))
			}
		}

		B.lane_sync_value(&ok, 0)

		if ok {
			B.lane_sync_value(&bin_codes, 0)

			bin_code_rng := B.lane_range(len(bin_codes))
			for i in bin_code_rng.start..<bin_code_rng.end {
				tdata.module.codes[i], _ = bin_read_code(ctx, bin_codes[i])
			}
		}
	}

	B.lane_sync()

	if lane == 0 {
		tdata.diags^ = bin_collect_diagnostics(ctx.arena, ctxs)
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
	per_thread_tdata := B.arena_push_make(temp, []Bin_Thread_Data, thread_count)

	for &tdata, i in per_thread_tdata {
		tdata.lane_ctx.index = i
		tdata.lane_ctx.count = thread_count
		tdata.lane_ctx.barrier = &barrier
		tdata.lane_ctx.shared_memory = &lane_shared_memory

		tdata.module = &module
		tdata.diags  = &diags
		tdata.arenas = thread_arenas
		tdata.done = &done_one_shot_event
		tdata.data = data
		tdata.file = file_name

		tdata.thread = thread.create(bin_read_entry_point, name = fmt.aprintf("wasim_%v", i, allocator = temp))
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
