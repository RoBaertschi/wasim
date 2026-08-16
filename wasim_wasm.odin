package wasim

import "core:strings"
import "core:os"
import "core:fmt"
import "core:sync"
import "core:flags"
import "core:thread"
import "core:sys/info"
import "core:encoding/varint"

import "base:runtime"
import "base:intrinsics"

import B "base"

import T "tracy"

MAGIC   :: u32(0x6D736100)
VERSION :: u32(1)

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

	file: string,
	errors: int,
	m: ^Module,
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
	I32 = 0x7F,
	I64 = 0x7E,
	U32 = 0x7D,
	U64 = 0x7C,
}

Function_Type :: struct {
	args: []Value_Type,
	rets: []Value_Type,
}

Type_Index :: distinct u32

Local :: struct {
	type:   Value_Type,
	repeat: u32,
}

Instruction :: struct {}

Code :: struct {
	pos:  int,
	data: []byte,

	locals: []Local,
	expr:   []Instruction,
}

Section :: struct {
	kind:  Section_Kind,
	pos:   int,
	data:  []byte,
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

reader_arena :: proc(ctx: ^Read_Ctx) -> ^B.Arena {
	return ctx.m.arenas[B.lane_idx()]
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

	ctx.errors += 1

	fmt.printf("%v:%v: WASM Binary Error: ", ctx.file, range.start)
	fmt.printfln(format, ..args)
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
	start := reader_anchor(ctx)
	
	value_type_byte: byte
	value_type_byte, ok = read_byte(ctx)

	if ok {
		if value_type_byte <= byte(max(Value_Type)) {
			value_type = Value_Type(value_type_byte)
		} else {
			errorf(ctx, reader_anchor_range(ctx, start), "invalid value type %v: %v(0) <= %v(%v)", value_type_byte, min(Value_Type), max(Value_Type), byte(max(Value_Type)))
		}
	}

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

// Only reads the size of the code, not it's actual content
read_code_structure :: proc(ctx: ^Read_Ctx) -> (code: Code, ok: bool) {
	code.pos = reader_absolute_pos(ctx)
	size: int
	size, ok = as(int, read_u32_leb(ctx))
	if ok {
		code.data, ok = read_bytes(ctx, size)
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

read_code_section_structure :: proc(ctx: ^Read_Ctx) -> (codes: []Code, ok: bool) {
	codes, ok = read_vec(ctx, read_code_structure)
	return
}

read_module :: proc(data: []byte, file: string) -> (ok: bool) {
	temp := B.TEMP_ALLOCATOR_GUARD()
	ctx  := B.arena_push(temp, Read_Ctx)

	ctx.data = data
	ctx.file = file

	if B.lane_idx() == 0 {
		ctx.m        = B.arena_bootstrap_new(Module, "arena")
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
			if magic == MAGIC {
				ok = true
			} else {
				ok = false
				errorf(ctx, reader_anchor_range(ctx, anchor), "invalid magic number %v, expected %v", magic, MAGIC)
			}
		}

		anchor = reader_anchor(ctx)

		// read version number
		if ok {
			ctx.m.version, ok = read_u32(ctx)
			if ctx.m.version == VERSION {
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

				section := Section{
					pos = ctx.curr,
				}

				section.kind, ok = read_t(ctx, Section_Kind)
				if !ok {
					break
				}

				ok = u8(section.kind) <= u8(max(Section_Kind))
				if !ok {
					errorf(ctx, reader_anchor_range(ctx, start), "invalid section kind %d, expected 0..=%v", u8(section.kind), u8(max(Section_Kind)))
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
		case .Type:     section.types, _ = read_type_section(ctx)
		case .Import:   // unimplemented()
		case .Function: section.funcs, _ = read_func_section(ctx)
		case .Table:    // unimplemented()
		case .Memory:   // unimplemented()
		case .Global:   // unimplemented()
		case .Export:   // unimplemented()
		case .Start:    // unimplemented()
		case .Element:  // unimplemented()
		case .Code:     section.codes, _ = read_code_section_structure(ctx) // TODO(robin): split up into multiple units
		case .Data:     // unimplemented()
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
					return
				},
			)

			if ok {
				anchor := reader_anchor(ctx)
				end_byte: byte
				end_byte, ok = read_byte(ctx)

				if ok {
					if end_byte != 0x0B {
						errorf(ctx, reader_anchor_range(ctx, anchor), "unsupported instruction starting with byte %h", end_byte)
					}
				}
			}
		}
	}

	B.lane_sync()

	if B.lane_idx() == 0 {
		fmt.printfln("found module with version %v", m.version)
		for section in m.sections {
			fmt.printfln("found section of type %q: %v", section.kind, section)
		}
	}

	B.lane_sync()

	return
}

Thread_Data :: struct {
	lane_ctx: B.Lane_Ctx,
	thread: ^thread.Thread,
	data: []byte,
	file: string,
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
