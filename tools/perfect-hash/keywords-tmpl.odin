package wasim

NK :: $NK
NG :: $NG
NS :: $NS
NG1 :: NG - 1

tex_tok_perfect_hash := [?]int{$G}
tex_tok_perfect_hash_key := [?]string{$K}

tex_tok_perfect_hash_s1 := "$S1"
tex_tok_perfect_hash_s2 := "$S2"

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
