package wasim

import "core:slice"
import "core:math/bits"
import "core:container/xar"

import B "base"

Bin_Instruction_Builder :: struct {
	instructions: xar.Array(Instruction, 6),
	extras:        xar.Array(byte, 8),
}

bin_ib_push :: proc(ib: ^Bin_Instruction_Builder, opcode: Instruction_Opcode) -> (inst: ^Instruction, pos: u32) {
	pos     = u32(xar.len(ib.instructions))
	inst, _ = xar.push_back_elem_and_get_ptr(&ib.instructions, Instruction { opcode = opcode })
	return
}

bin_ib_push_extra_bytes :: proc(ib: ^Bin_Instruction_Builder, bytes: []byte) -> (pos: u32) {
	pos = u32(xar.len(ib.extras))
	xar.push_back(&ib.extras, ..bytes)
	return
}

bin_ib_push_extra_value :: proc(ib: ^Bin_Instruction_Builder, value: $T) -> (pos: u32) {
	value := value
	value_bytes := transmute([size_of(T)]byte)value
	pos = bin_ib_push_extra_bytes(ib, value_bytes[:])
	return
}

bin_ib_push_extra_u32 :: proc(ib: ^Bin_Instruction_Builder, value: u32) -> (pos: u32) {
	pos = bin_ib_push_extra_value(ib, value)
	return
}

bin_ib_push_extra_u64 :: proc(ib: ^Bin_Instruction_Builder, value: u64) -> (pos: u32) {
	pos = bin_ib_push_extra_value(ib, value)
	return
}

bin_ib_push_extra_f64 :: proc(ib: ^Bin_Instruction_Builder, value: f64) -> (pos: u32) {
	pos = bin_ib_push_extra_value(ib, value)
	return
}

bin_ib_push_extra_block_type :: proc(ib: ^Bin_Instruction_Builder, value_types: []Value_Type) -> (pos: u32) {
	assert(len(value_types) < bits.U8_MAX)
	pos = bin_ib_push_extra_value(ib, byte(len(value_types)))

	bin_ib_push_extra_bytes(ib, slice.reinterpret([]byte, value_types))
	return
}

bin_ib_push_extra :: proc{
	bin_ib_push_extra_u32,
	bin_ib_push_extra_u64,
	bin_ib_push_extra_f64,
	bin_ib_push_extra_block_type,
	bin_ib_push_extra_bytes,
}

bin_read_expr :: proc(ctx: ^Bin_Read_Ctx) -> (expr: Expr, ok: bool) {
	ib: Bin_Instruction_Builder

	temp := B.TEMP_ALLOCATOR_GUARD()
	xar.init(&ib.instructions, temp)
	xar.init(&ib.extras, temp)

	xar.push_back(&ib.instructions, Instruction {})
	xar.push_back(&ib.extras, 0)

	bin_read_block_type :: proc(ctx: ^Bin_Read_Ctx, arena: ^B.Arena) -> (block_type: []Value_Type, ok: bool) {
		anchor := bin_reader_anchor(ctx)

		block_type_byte: byte
		block_type_byte, ok = bin_read_byte(ctx)

		if ok {
			if block_type_byte == 0x40 {
				block_type = nil
			} else {
				block_type = B.arena_push_make(arena, []Value_Type, 1)
				block_type[0], ok = bin_read_validate_enum(ctx, anchor, block_type_byte, Value_Type, "value type")
			}
		}

		return
	}

	bin_read_opcode :: proc(ctx: ^Bin_Read_Ctx) -> (opcode: Instruction_Opcode, ok: bool) {
		opcode, ok = bin_as(Instruction_Opcode, bin_read_byte(ctx))
		return
	}

	bin_read_instructions_until :: proc(ctx: ^Bin_Read_Ctx, ib: ^Bin_Instruction_Builder, until: ..Instruction_Opcode) -> (break_opcode: Instruction_Opcode, ok: bool) {
		temp := B.TEMP_ALLOCATOR_GUARD()

		anchor := bin_reader_anchor(ctx)

		outer: for {
			opcode: Instruction_Opcode
			opcode, ok = bin_read_opcode(ctx)

			inst, pos := bin_ib_push(ib, opcode)

			#unroll(2) for u in until {
				if u == opcode {
					break_opcode = u
					break outer
				}
			}

			#partial switch inst.opcode {
			case .Else: unreachable()
			case .End:  unreachable()

			case .Unreachable, .Nop: // nothing

			case .Block, .Loop:
				// read block type
				block_type: []Value_Type
				block_type, ok = bin_read_block_type(ctx, temp)

				// read instructions
				if ok {
					inst.extra = bin_ib_push_extra(ib, block_type)
					_, ok = bin_read_instructions_until(ctx, ib, .End)
					bin_ib_push_extra(ib, pos + 1)
				}
			case .If:
				// read block type
				block_type: []Value_Type
				block_type, ok = bin_read_block_type(ctx, temp)

				// stores the last opcode for the first list of instructions
				// to flatten the code a bit, we pulled it out of the if
				last: Instruction_Opcode

				// read if instructions
				if ok {
					inst.extra = bin_ib_push_extra(ib, block_type)

					last, ok = bin_read_instructions_until(ctx, ib, .End, .Else)
					bin_ib_push_extra(ib, pos + 1)
				}

				// read else instructions
				if ok {
					if_last_pos := xar.len(ib.instructions)

					if last == .Else {
						_, ok = bin_read_instructions_until(ctx, ib, .End)
					} else {
						if_last_pos = 0
					}
					bin_ib_push_extra(ib, u32(if_last_pos))
				}

			case .Br, .Br_If:
				// read labelidx
				inst.extra, ok = bin_read_u32_leb(ctx)

			case .Br_Table:
				// read labels
				labels: []u32
				labels, ok = bin_read_vec(ctx, bin_read_u32_leb, temp)
				if ok {
					inst.extra = bin_ib_push_extra(ib, u32(len(labels)))
					bin_ib_push_extra(ib, slice.reinterpret([]byte, labels))

					// read default label
					default_label: u32
					default_label, ok = bin_read_u32_leb(ctx)
					if ok {
						bin_ib_push_extra(ib, default_label)
					}
				}

			case .Return: // nothing
			case .Call:
				// read funcidx
				inst.extra, ok = bin_read_u32_leb(ctx)

			case .Call_Indirect:
				inst.extra, ok = bin_read_u32_leb(ctx)
				if ok {
					anchor = bin_reader_anchor(ctx)

					extra_useless: byte
					extra_useless, ok = bin_read_byte(ctx)
					if extra_useless != 0 {
						bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "call_indirect second number is not 0x00, which is not supported in WASM Core 1")
					}
				}

			case .Drop, .Select: // nothing

			case .Local_Get..=.Global_Set:
				// read localidx/globalidx
				inst.extra, ok = bin_read_u32_leb(ctx)

			case .I32_Load..=.I64_Store32:
				align, offset: u32
				align, ok = bin_read_u32_leb(ctx)
				if ok {
					offset, ok = bin_read_u32_leb(ctx)
				}

				if ok {
					inst.extra = bin_ib_push_extra(ib, align)
					bin_ib_push_extra(ib, offset)
				}

			case .Memory_Size..=.Memory_Grow:
				extra_useless: byte
				extra_useless, ok = bin_read_byte(ctx)
				if extra_useless != 0 {
					bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "memory.size/memory.grow first number is not 0x00, which is not supported in WASM Core 1")
				}

			case .I32_Const:
				// read constant
				inst.extra, ok = bin_as(u32, bin_read_i32_leb(ctx))

			case .I64_Const:
				// read constant
				constant: u64
				constant, ok = bin_as(u64, bin_read_i64_leb(ctx))
				if ok {
					inst.extra = bin_ib_push_extra(ib, constant)
				}

			case .F32_Const:
				// read constant
				// NOTE: unlike integers, float constants are full size with no compression
				inst.extra, ok = bin_read_u32(ctx)

			case .F64_Const:
				// read constant
				// NOTE: unlike integers, float constants are full size with no compression
				constant: u64
				constant, ok = bin_as(u64, bin_read_u64(ctx))
				if ok {
					inst.extra = bin_ib_push_extra(ib, constant)
				}

			case .I32_Eqz..=.F64_Reinterpret_I64: // nothing

			case: bin_errorf(ctx, bin_reader_anchor_range(ctx, anchor), "invalid opcode %v", inst.opcode)
			}
		}

		return
	}

	bin_read_instructions_until(ctx, &ib, .End)

	expr.instructions = B.arena_push_make(bin_reader_arena(ctx), []Instruction, xar.len(ib.instructions))
	expr.extras       = B.arena_push_make(bin_reader_arena(ctx), []byte, xar.len(ib.extras))

	for it := xar.iterator(&ib.instructions); inst, i in xar.iterate_by_val(&it) {
		expr.instructions[i] = inst
	}

	for it := xar.iterator(&ib.extras); extra, i in xar.iterate_by_val(&it) {
		expr.extras[i] = extra
	}

	return
}
