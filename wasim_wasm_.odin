package wasim

Limits_Kind :: enum u8 {
	Unlimited,
	Limited,
}

Limits :: struct {
	kind: Limits_Kind,
	min:  u32,
	max:  u32,
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
	Invalid = 0xFF, // Not assigned in WebAssembly Core 1.

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

// NOTE: The actual instruction data starts at 1, not 0
//       0 is a dummy sentinel used for optional values that are not there
Expr :: struct {
	instructions: []Instruction,
	extras:       []byte,
}

Code :: struct {
	locals: []Local,
	expr:   Expr,
}

Data :: struct {
	index: u32,
	expr:  Expr,
	init:  []byte,
}

Module :: struct {
	version: u32,

	types:     []Function_Type,
	tables:    []Table_Type,
	imps:      []Import, // import is a keyword, so we just use imp instead
	functions: []Type_Index,
	memory:    []Memory,
	globals:   []Global,
	exports:   []Export,
	start:     u32,
	elements:  []Element,
	codes:     []Code,
	datas:     []Data,
}
