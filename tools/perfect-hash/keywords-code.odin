package wasim

NK :: 194
NG :: 283
NS :: 19
NG1 :: NG - 1

tex_tok_perfect_hash := [?]int{0, 0, 0, 196, 0, 205, 33, 0, 196, 0, 0, 0, 0, 136, 0,
    271, 0, 0, 0, 188, 210, 199, 66, 199, 0, 124, 47, 83, 48, 257, 240, 0,
    0, 128, 0, 228, 0, 0, 73, 0, 124, 0, 62, 28, 233, 140, 87, 0, 0, 18, 0,
    30, 118, 3, 232, 81, 0, 0, 25, 44, 205, 0, 166, 40, 0, 0, 0, 211, 107,
    262, 0, 104, 1, 169, 17, 226, 78, 76, 142, 149, 169, 264, 9, 64, 0, 99,
    67, 8, 88, 0, 166, 0, 99, 63, 0, 168, 73, 0, 0, 0, 38, 238, 0, 155,
    173, 6, 81, 0, 268, 279, 226, 176, 258, 152, 107, 70, 250, 0, 0, 0, 18,
    0, 148, 0, 0, 176, 0, 188, 228, 0, 100, 276, 0, 275, 111, 84, 16, 206,
    232, 9, 236, 130, 95, 248, 199, 25, 0, 0, 0, 25, 63, 0, 88, 243, 232,
    0, 0, 47, 61, 229, 111, 0, 85, 134, 0, 0, 12, 130, 5, 0, 233, 0, 107,
    106, 85, 278, 139, 26, 84, 0, 0, 0, 225, 102, 0, 224, 92, 199, 261, 0,
    163, 150, 175, 172, 87, 131, 0, 234, 202, 279, 123, 0, 0, 115, 47, 22,
    0, 125, 273, 142, 122, 0, 265, 0, 138, 139, 244, 175, 263, 0, 31, 246,
    0, 256, 44, 225, 94, 0, 0, 0, 228, 0, 72, 0, 99, 99, 276, 216, 0, 226,
    60, 65, 0, 0, 91, 127, 0, 237, 76, 75, 11, 20, 4, 23, 111, 115, 0, 84,
    124, 149, 0, 241, 183, 0, 216, 65, 0, 155, 37, 59, 0, 0, 69, 265, 0,
    152, 128, 79, 270, 106, 112, 70, 173}
tex_tok_perfect_hash_key := [?]string{"i32", "i64", "f32", "f64", "i32.const", "i64.const",
    "f32.const", "f64.const", "funcref", "mut", "nop", "unreachable",
    "drop", "block", "loop", "end", "br", "br_if", "br_table", "return",
    "if", "then", "else", "select", "call", "call_indirect", "local.get",
    "local.set", "local.tee", "global.get", "global.set", "i32.load",
    "i64.load", "f32.load", "f64.load", "i32.store", "i64.store",
    "f32.store", "f64.store", "i32.load8_s", "i32.load8_u", "i32.load16_s",
    "i32.load16_u", "i64.load8_s", "i64.load8_u", "i64.load16_s",
    "i64.load16_u", "i64.load32_s", "i64.load32_u", "i32.store8",
    "i32.store16", "i64.store8", "i64.store16", "i64.store32", "i32.clz",
    "i32.ctz", "i32.popcnt", "i64.clz", "i64.ctz", "i64.popcnt", "f32.neg",
    "f32.abs", "f32.sqrt", "f32.ceil", "f32.floor", "f32.trunc",
    "f32.nearest", "f64.neg", "f64.abs", "f64.sqrt", "f64.ceil",
    "f64.floor", "f64.trunc", "f64.nearest", "i32.add", "i32.sub",
    "i32.mul", "i32.div_s", "i32.div_u", "i32.rem_s", "i32.rem_u",
    "i32.and", "i32.or", "i32.xor", "i32.shl", "i32.shr_s", "i32.shr_u",
    "i32.rotl", "i32.rotr", "i64.add", "i64.sub", "i64.mul", "i64.div_s",
    "i64.div_u", "i64.rem_s", "i64.rem_u", "i64.and", "i64.or", "i64.xor",
    "i64.shl", "i64.shr_s", "i64.shr_u", "i64.rotl", "i64.rotr", "f32.add",
    "f32.sub", "f32.mul", "f32.div", "f32.min", "f32.max", "f32.copysign",
    "f64.add", "f64.sub", "f64.mul", "f64.div", "f64.min", "f64.max",
    "f64.copysign", "i32.eqz", "i64.eqz", "i32.eq", "i32.ne", "i32.lt_s",
    "i32.lt_u", "i32.le_s", "i32.le_u", "i32.gt_s", "i32.gt_u", "i32.ge_s",
    "i32.ge_u", "i64.eq", "i64.ne", "i64.lt_s", "i64.lt_u", "i64.le_s",
    "i64.le_u", "i64.gt_s", "i64.gt_u", "i64.ge_s", "i64.ge_u", "f32.eq",
    "f32.ne", "f32.lt", "f32.le", "f32.gt", "f32.ge", "f64.eq", "f64.ne",
    "f64.lt", "f64.le", "f64.gt", "f64.ge", "i32.wrap_i64",
    "i64.extend_i32_s", "i64.extend_i32_u", "f32.demote_f64",
    "f64.promote_f32", "i32.trunc_f32_s", "i32.trunc_f32_u",
    "i32.trunc_f64_s", "i32.trunc_f64_u", "i64.trunc_f32_s",
    "i64.trunc_f32_u", "i64.trunc_f64_s", "i64.trunc_f64_u",
    "f32.convert_i32_s", "f32.convert_i32_u", "f32.convert_i64_s",
    "f32.convert_i64_u", "f64.convert_i32_s", "f64.convert_i32_u",
    "f64.convert_i64_s", "f64.convert_i64_u", "f32.reinterpret_i32",
    "f64.reinterpret_i64", "i32.reinterpret_f32", "i64.reinterpret_f64",
    "memory.size", "memory.grow", "type", "func", "start", "param",
    "result", "local", "global", "table", "memory", "elem", "data",
    "offset", "import", "export", "module"}

tex_tok_perfect_hash_s1 := "0YzP9awKysIXge49wq5"
tex_tok_perfect_hash_s2 := "qw92gn0Ii8IBQzkTkdV"

tex_tok_perfect_hash_proc :: proc(key: string) -> (index: int) {
	if len(key) <= NS {
		f1, f2: int

		remainder :: #force_inline proc(value: int) -> int {
			when 0 < NG && (NG & (NG-1)) == 0 {
				return value & (NG - 1)
			} else {
				return value % NG
			}
		}

		for c, i in transmute([]byte)key {
			f1 += int(tex_tok_perfect_hash_s1[i]) * int(c)
			f2 += int(tex_tok_perfect_hash_s2[i]) * int(c)
		}

		index = remainder(tex_tok_perfect_hash[remainder(f1)] + tex_tok_perfect_hash[remainder(f2)])
		if index < NK && key == tex_tok_perfect_hash_key[index] {
			return
		}
	}

	return -1
}

import "core:testing"

@test
tex_tok_perfect_hash_test :: proc(t: ^testing.T) {
	for k, i in tex_tok_perfect_hash_key {
		testing.expect_value(t, tex_tok_perfect_hash_proc(k), i)
	}
}
