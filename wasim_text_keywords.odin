package wasim

NK :: 194
NG :: 297
NS :: 19
NG1 :: NG - 1

tex_tok_perfect_hash := [?]int{0, 102, 2, 0, 62, 54, 269, 0, 0, 274, 112, 0, 187, 213, 
    0, 0, 67, 163, 0, 0, 287, 0, 0, 52, 195, 0, 98, 0, 260, 141, 233, 0, 
    224, 0, 0, 0, 151, 0, 12, 0, 27, 0, 0, 0, 0, 0, 206, 0, 261, 0, 0, 0, 
    0, 0, 0, 25, 6, 156, 259, 0, 0, 118, 223, 0, 285, 154, 107, 0, 246, 0, 
    211, 0, 268, 189, 29, 202, 244, 0, 153, 0, 0, 253, 35, 110, 39, 104, 0, 
    153, 0, 0, 156, 99, 0, 89, 190, 256, 0, 244, 44, 134, 0, 0, 0, 0, 0, 
    141, 138, 34, 16, 150, 1, 251, 193, 0, 0, 33, 247, 109, 0, 0, 78, 113, 
    0, 0, 191, 234, 55, 5, 183, 0, 100, 215, 123, 0, 163, 0, 31, 66, 24, 0, 
    13, 0, 201, 0, 42, 21, 87, 155, 200, 227, 47, 0, 267, 4, 0, 100, 0, 0, 
    289, 63, 149, 134, 0, 0, 0, 191, 286, 0, 69, 0, 18, 0, 0, 284, 0, 131, 
    83, 264, 187, 223, 164, 247, 120, 85, 152, 0, 0, 269, 141, 293, 290, 
    25, 262, 44, 173, 54, 245, 97, 152, 0, 133, 0, 0, 135, 137, 37, 123, 
    32, 0, 82, 37, 228, 0, 23, 8, 0, 145, 83, 199, 0, 250, 0, 81, 174, 99, 
    219, 143, 189, 0, 136, 0, 190, 166, 200, 196, 75, 163, 34, 0, 128, 0, 
    242, 92, 0, 178, 45, 110, 245, 182, 143, 113, 55, 67, 27, 0, 41, 93, 
    203, 178, 144, 0, 19, 146, 258, 0, 186, 199, 181, 237, 0, 0, 293, 0, 0, 
    96, 85, 0, 176, 16, 0, 94, 0, 17, 0, 118, 145, 213, 0, 220, 4, 37, 0, 
    219, 0, 73, 269, 120}
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

tex_tok_perfect_hash_s1 := "YcDM2XZP6VF8FNVf5JB"
tex_tok_perfect_hash_s2 := "jR2mvGtQtUO4PCUuUuj"

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
