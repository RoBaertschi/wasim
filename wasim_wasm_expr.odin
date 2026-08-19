package wasim

import "core:slice"
import "core:math/bits"
import "core:container/xar"

import B "base"

read_expr :: proc(ctx: ^Read_Ctx) -> (insts: []Instruction, ok: bool) {
	Instruction_Builder :: struct {
		instructions: xar.Array(Instruction, 6),
		extra:        xar.Array(byte, 8),
	}

	ib_push :: proc(ib: ^Instruction_Builder, opcode: Instruction_Opcode) -> (inst: ^Instruction, pos: u32) {
		pos     = u32(xar.len(ib.instructions))
		inst, _ = xar.push_back_elem_and_get_ptr(&ib.instructions, Instruction { opcode = opcode })
		return
	}

	ib_push_extra_bytes :: proc(ib: ^Instruction_Builder, bytes: []byte) -> (pos: u32) {
		pos = u32(xar.len(ib.extra))
		xar.push_back(&ib.extra, ..bytes)
		return
	}

	ib_push_extra_value :: proc(ib: ^Instruction_Builder, value: $T) -> (pos: u32) {
		value := value
		value_bytes := transmute([size_of(T)]byte)value
		pos = ib_push_extra_bytes(ib, value_bytes[:])
		return
	}

	ib_push_extra_block_type :: proc(ib: ^Instruction_Builder, value_types: []Value_Type) -> (pos: u32) {
		assert(len(value_types) < bits.U8_MAX)
		pos = ib_push_extra_value(ib, byte(len(value_types)))

		ib_push_extra_bytes(ib, slice.reinterpret([]byte, value_types))
		return
	}

	ib_push_extra :: proc{
		ib_push_extra_bytes,
		ib_push_extra_value,
	}

	ib: Instruction_Builder

	temp := B.TEMP_ALLOCATOR_GUARD()
	xar.init(&ib.instructions, temp)
	xar.init(&ib.extra, temp)

	read_block_type :: proc(ctx: ^Read_Ctx, arena: ^B.Arena) -> (block_type: []Value_Type, ok: bool) {
		anchor := reader_anchor(ctx)

		block_type_byte: byte
		block_type_byte, ok = read_byte(ctx)

		if ok {
			if block_type_byte == 0x40 {
				block_type = nil
			} else {
				block_type = B.arena_push_make(arena, []Value_Type, 1)
				block_type[0], ok = read_validate_enum(ctx, anchor, block_type_byte, Value_Type, "value type")
			}
		}

		return
	}

	read_opcode :: proc(ctx: ^Read_Ctx) -> (opcode: Instruction_Opcode, ok: bool) {
		opcode, ok = as(Instruction_Opcode, read_byte(ctx))
		return
	}

	read_instructions_until :: proc(ctx: ^Read_Ctx, ib: ^Instruction_Builder, until: Instruction_Opcode) -> (ok: bool) {
		temp := B.TEMP_ALLOCATOR_GUARD()

		anchor := reader_anchor(ctx)

		for {
			opcode: Instruction_Opcode
			opcode, ok = read_opcode(ctx)

			inst, pos := ib_push(ib, opcode)

			if inst.opcode == until {
				break
			}

			#partial switch inst.opcode {
			case .Else: unreachable()
			case .End:  unreachable()

			case .Unreachable, .Nop: // nothing

			case .Block, .Loop:
				block_type: []Value_Type
				block_type, ok = read_block_type(ctx, temp)

				if ok {
					inst.extra = ib_push_extra(ib, block_type)
					ok = read_instructions_until(ctx, ib, .End)
					ib_push_extra(ib, pos + 1)
				}

			case .Local_Get:
				// read localidx
				inst.extra, ok = read_u32_leb(ctx)
			case .I32_Const:
				// read constant
				inst.extra, ok = as(u32, read_i32_leb(ctx))
			case: errorf(ctx, reader_anchor_range(ctx, anchor), "unsupported/invalid opcode %v", inst.opcode)
			}
		}

		return
	}

	read_instructions_until(ctx, &ib, .End)

	// ok = true
	// for {
	// 	inst: Instruction
	// 	inst, ok = read_instruction(ctx)
	// 	if !ok {
	// 		break
	// 	}

	// 	append(&insts_dynamic_array, inst)

	// 	if inst.opcode == .End {
	// 		break
	// 	}
	// }

	// shrink(&insts_dynamic_array)
	// insts = insts_dynamic_array[:]
	return
}
