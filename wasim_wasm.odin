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

Limits_Kind :: enum u8 {
	Unlimited,
	Limited,
}

Limits :: struct {
	kind: Limits_Kind,
	min:  u32,
	max:  u32,
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
	F32 = 0x7D,
	F64 = 0x7C,
}

Function_Type :: struct {
	args: []Value_Type,
	rets: []Value_Type,
}

External_Kind :: enum u8 {
	Func,
	Table,
	Mem,
	Global,
}

Element_Type :: enum u8 {
	Func_Ref = 0x70,
}

Table_Type :: struct {
	element_type: Element_Type,
	limits:       Limits,
}

Global_Type :: struct {
	mutable: b8,
	type:    Value_Type,
}

Import :: struct {
	kind:   External_Kind,
	module: string,
	name:   string,

	using _: struct #raw_union {
		type_index:  u32         `raw_union_tag:"kind=Func"  `, // for Func
		table_type:  Table_Type  `raw_union_tag:"kind=Table" `, // for Table
		mem_type:    Memory      `raw_union_tag:"kind=Mem"   `, // for Mem
		global_type: Global_Type `raw_union_tag:"kind=Global"`, // for Global
	},
}

Type_Index :: distinct u32

Local :: struct {
	type:   Value_Type,
	repeat: u32,
}

Memory :: distinct Limits

Global :: struct {
	mutable: b8,
	type:    Value_Type,
	expr:    Expr,
}

Export :: struct {
	kind: External_Kind,
	name: string,
	index: u32,
}

Element :: struct {
	index: u32,
	expr:  Expr,
	init:  []u32,
}

// # Instruction Encoding
// Instructions are encoded in various ways, if they need more than 4 bytes to be encoded, the extra stack
// is used to store the extra data, then the decoder stores a position into the stack in `extra`.
//
// Besides each opcode, we comment how it is encoded. If nothing, then no comment, if only extra than extra=...
// and if none of the ones before, we list the decoded extras like this: `// Value_Type, ^Instruction`.
// Each of those strings before the comma correspond to some common encoding, which are listed below.
//
// # Common Encodings
//
// ## Value_Type
// The byte of the Value_Type
//
// ## ^Instruction
// Points to another instruction in the instruction stack, this is an u32 as an index into the stack.
//
// ## Maybe(^Instruction)
// If zero, this does not point anywhere, anything else is to be interpreted like ^Instruction.
//
// ## Block_Type
// This encodes a []Value_Type, first comes a byte(TODO(robin): find out what the return limits actually are) with the
// size of the Value_Type and following it are that amount of Value_Type's.
//
// ## labelidx(u32)
// Labelidx represented as a u32.
//
// ## funcidx(u32)
// Funcidx represented as a u32.
//
// ## typeidx(u32)
// Typeidx represented as a u32.
//
// ## localidx(u32)
// Localidx represented as a u32.
//
// ## globalidx(u32)
// Globalidx represented as a u32.
//
// ## []$E
// Vec of `E`, starts with a `size` represented as a u32, then following it are E\[`size`\] elements.
//
// ## memarg
// Align is a u32 followed by a u32 for the offset.
Instruction_Opcode :: enum u8 {
	// §5.4.1 Control Instructions
	Unreachable   = 0x00,
	Nop           = 0x01,
	Block         = 0x02, // Block_Type, ^Instruction
	Loop          = 0x03, // Block_Type, ^Instruction

	// NOTE: else is optional
	// Block_Type, ^Instruction, Maybe(^Instruction)
	If            = 0x04,
	Br            = 0x0C, // extra=labelidx(u32)
	Br_If         = 0x0D, // extra=labelidx(u32)
	Br_Table      = 0x0E, // []labelidx(u32), labelidx(u32)
	Return        = 0x0F,
	Call          = 0x10, // extra=funcidx(u32)
	Call_Indirect = 0x11, // extra=funcidx(u32)

	// §5.4.2 Parametric Instructions
	Drop   = 0x1A,
	Select = 0x1B,

	// §5.4.3 Variable Instructions
	Local_Get  = 0x20, // extra=localidx(u32)
	Local_Set  = 0x21, // extra=localidx(u32)
	Local_Tee  = 0x22, // extra=localidx(u32)
	Global_Get = 0x23, // extra=globalidx(u32)
	Global_Set = 0x24, // extra=globalidx(u32)

	// §5.4.4 Memory Instructions
	I32_Load = 0x28, // memarg
	I64_Load = 0x29, // memarg
	F32_Load = 0x2A, // memarg
	F64_Load = 0x2B, // memarg

	I32_Load8_s  = 0x2C, // memarg
	I32_Load8_u  = 0x2D, // memarg
	I32_Load16_s = 0x2E, // memarg
	I32_Load16_u = 0x2F, // memarg

	I64_Load8_s  = 0x30, // memarg
	I64_Load8_u  = 0x31, // memarg
	I64_Load16_s = 0x32, // memarg
	I64_Load16_u = 0x33, // memarg
	I64_Load32_s = 0x34, // memarg
	I64_Load32_u = 0x35, // memarg

	I32_Store = 0x36, // memarg
	I64_Store = 0x37, // memarg
	F32_Store = 0x38, // memarg
	F64_Store = 0x39, // memarg

	I32_Store8  = 0x3A, // memarg
	I32_Store16 = 0x3B, // memarg

	I64_Store8  = 0x3C, // memarg
	I64_Store16 = 0x3D, // memarg
	I64_Store32 = 0x3E, // memarg

	Memory_Size = 0x3F,
	Memory_Grow = 0x40,

	// §5.4.5 Numeric Instructions
	I32_Const = 0x41, // extra=u32
	I64_Const = 0x42, // u64
	F32_Const = 0x43, // extra=f32
	F64_Const = 0x44, // f64

	I32_Eqz  = 0x45,
	I32_Eq   = 0x46,
	I32_Ne   = 0x47,
	I32_Lt_s = 0x48,
	I32_Lt_u = 0x49,
	I32_Gt_s = 0x4A,
	I32_Gt_u = 0x4B,
	I32_Le_s = 0x4C,
	I32_Le_u = 0x4D,
	I32_Ge_s = 0x4E,
	I32_Ge_u = 0x4F,

	I64_Eqz  = 0x50,
	I64_Eq   = 0x51,
	I64_Ne   = 0x52,
	I64_Lt_s = 0x53,
	I64_Lt_u = 0x54,
	I64_Gt_s = 0x55,
	I64_Gt_u = 0x56,
	I64_Le_s = 0x57,
	I64_Le_u = 0x58,
	I64_Ge_s = 0x59,
	I64_Ge_u = 0x5A,

	F32_Eq = 0x5B,
	F32_Ne = 0x5C,
	F32_Lt = 0x5D,
	F32_Gt = 0x5E,
	F32_Le = 0x5F,
	F32_Ge = 0x60,

	F64_Eq = 0x61,
	F64_Ne = 0x62,
	F64_Lt = 0x63,
	F64_Gt = 0x64,
	F64_Le = 0x65,
	F64_Ge = 0x66,

	I32_Clz    = 0x67,
	I32_Ctz    = 0x68,
	I32_Popcnt = 0x69,
	I32_Add    = 0x6A,
	I32_Sub    = 0x6B,
	I32_Mul    = 0x6C,
	I32_Div_s  = 0x6D,
	I32_Div_u  = 0x6E,
	I32_Rem_s  = 0x6F,
	I32_Rem_u  = 0x70,
	I32_And    = 0x71,
	I32_Or     = 0x72,
	I32_Xor    = 0x73,
	I32_Shl    = 0x74,
	I32_Shr_s  = 0x75,
	I32_Shr_u  = 0x76,
	I32_Rotl   = 0x77,
	I32_Rotr   = 0x78,

	I64_Clz    = 0x79,
	I64_Ctz    = 0x7A,
	I64_Popcnt = 0x7B,
	I64_Add    = 0x7C,
	I64_Sub    = 0x7D,
	I64_Mul    = 0x7E,
	I64_Div_s  = 0x7F,
	I64_Div_u  = 0x80,
	I64_Rem_s  = 0x81,
	I64_Rem_u  = 0x82,
	I64_And    = 0x83,
	I64_Or     = 0x84,
	I64_Xor    = 0x85,
	I64_Shl    = 0x86,
	I64_Shr_s  = 0x87,
	I64_Shr_u  = 0x88,
	I64_Rotl   = 0x89,
	I64_Rotr   = 0x8A,

	F32_Abs      = 0x8B,
	F32_Neg      = 0x8C,
	F32_Ceil     = 0x8D,
	F32_Floor    = 0x8E,
	F32_Trunc    = 0x8F,
	F32_Nearest  = 0x90,
	F32_Sqrt     = 0x91,
	F32_Add      = 0x92,
	F32_Sub      = 0x93,
	F32_Mul      = 0x94,
	F32_Div      = 0x95,
	F32_Min      = 0x96,
	F32_Max      = 0x97,
	F32_Copysign = 0x98,

	F64_Abs      = 0x99,
	F64_Neg      = 0x9A,
	F64_Ceil     = 0x9B,
	F64_Floor    = 0x9C,
	F64_Trunc    = 0x9D,
	F64_Nearest  = 0x9E,
	F64_Sqrt     = 0x9F,
	F64_Add      = 0xA0,
	F64_Sub      = 0xA1,
	F64_Mul      = 0xA2,
	F64_Div      = 0xA3,
	F64_Min      = 0xA4,
	F64_Max      = 0xA5,
	F64_Copysign = 0xA6,

	I32_Wrap_I64        = 0xA7,
	I32_Trunc_F32_s     = 0xA8,
	I32_Trunc_F32_u     = 0xA9,
	I32_Trunc_F64_s     = 0xAA,
	I32_Trunc_F64_u     = 0xAB,
	I64_Extend_I32_s    = 0xAC,
	I64_Extend_I32_u    = 0xAD,
	I64_Trunc_F32_s     = 0xAE,
	I64_Trunc_F32_u     = 0xAF,
	I64_Trunc_F64_s     = 0xB0,
	I64_Trunc_F64_u     = 0xB1,
	F32_Convert_I32_s   = 0xB2,
	F32_Convert_I32_u   = 0xB3,
	F32_Convert_I64_s   = 0xB4,
	F32_Convert_I64_u   = 0xB5,
	F32_Demote_F64      = 0xB6,
	F64_Convert_I32_s   = 0xB7,
	F64_Convert_I32_u   = 0xB8,
	F64_Convert_I64_s   = 0xB9,
	F64_Convert_I64_u   = 0xBA,
	F64_Promote_F32     = 0xBB,
	I32_Reinterpret_F32 = 0xBC,
	I64_Reinterpret_F64 = 0xBD,
	F32_Reinterpret_I32 = 0xBE,
	F64_Reinterpret_I64 = 0xBF,

	// Other
	Else = 0x05,
	End  = 0x0B,
}

Instruction :: struct {
	opcode: Instruction_Opcode,
	// this stores extra data, either inline or externally in an arena
	// it depends on the instruction, where this data is
	extra:  u32,
}

Expr :: struct {
	instructions: []Instruction,
	extras:       []byte,
}

Code :: struct {
	pos:  int,
	data: []byte,

	locals: []Local,
	expr:   Expr,
}

Data :: struct {
	index: u32,
	expr:  Expr,
	init:  []byte,
}

Section :: struct {
	kind:      Section_Kind,
	pos:       int,
	data:      []byte,

	using _: struct #raw_union {
		types:     []Function_Type `raw_union_tag:"kind=Type"`,
		tables:    []Table_Type    `raw_union_tag:"kind=Table"`,
		imps:      []Import        `raw_union_tag:"kind=Import"`, // import is a keyword, so we just use imp instead
		functions: []Type_Index    `raw_union_tag:"kind=Function"`,
		memory:    []Memory        `raw_union_tag:"kind=Memory"`,
		globals:   []Global        `raw_union_tag:"kind=Global"`,
		exports:   []Export        `raw_union_tag:"kind=Export"`,
		start:     u32             `raw_union_tag:"kind=Start"`,
		elements:  []Element       `raw_union_tag:"kind=Element"`,
		codes:     []Code          `raw_union_tag:"kind=Code"`,
		datas:     []Data          `raw_union_tag:"kind=Data"`,
	},
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
read_code_structure :: proc(ctx: ^Read_Ctx) -> (code: Code, ok: bool) {
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

read_code_section_structure :: proc(ctx: ^Read_Ctx) -> (codes: []Code, ok: bool) {
	codes, ok = read_vec(ctx, read_code_structure)
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
