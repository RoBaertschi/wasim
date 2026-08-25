package wasim

// NOTE: these are based on the actual implementation from strconv, because we require accurate f32 parsing, we needed to add our own implementation
//       most of this is written by AI, so do not fully trust it

import "core:strconv/decimal"
import "core:strconv"
import "core:testing"

// This parser adapts core:strconv.parse_f64 to round directly to either f32 or
// f64. It changes two conditions in parse_f64's hexadecimal path:
// - The second mantissa-normalization loop uses != 0 instead of repeating the
//   first loop's == 0. The repeated condition leaves mantissas wider than the
//   available precision unshifted and produces incorrect bits.
// - Subnormal adjustment uses a for loop instead of an if, because very small
//   values can require multiple right shifts. A single shift produces incorrect
//   subnormals and can prevent values below the halfway point from becoming zero.
// The hexadecimal regression cases below cover both changes.
tex_parse_float :: proc($T: typeid, s: string, info: ^strconv.Float_Info) -> (value: T, overflow: bool)
	where T == f32 || T == f64 {
	bits_to_float :: #force_inline proc "contextless" ($T: typeid, bits: u64) -> T {
		when T == f32 {
			return transmute(f32)u32(bits)
		} else when T == f64 {
			return transmute(f64)bits
		}
	}
	lower :: #force_inline proc "contextless" (ch: byte) -> byte {
		return ('a' - 'A') | ch
	}

	parse_components :: proc(s: string) -> (mantissa: u64, exp: int, neg, trunc, hex: bool, i: int, ok: bool) {
		if len(s) == 0 {
			return
		}
		switch s[i] {
		case '+': i += 1
		case '-': i += 1; neg = true
		}

		base := u64(10)
		MAX_MANT_DIGITS := 19
		exp_char := byte('e')

		if i+2 < len(s) && s[i] == '0' && lower(s[i+1]) == 'x' {
			base = 16
			MAX_MANT_DIGITS = 16
			exp_char = 'p'
			hex = true
			i += 2
		}

		saw_dot, saw_digits := false, false
		nd := 0
		nd_mant := 0
		decimal_point := 0
		trailing_zeroes_nd := -1

		loop: for ; i < len(s); i += 1 {
			switch c := s[i]; true {
			case c == '_':
				continue loop
			case c == '.':
				assert(!saw_dot)
				saw_dot = true
				decimal_point = nd
				continue loop
			case '0' <= c && c <= '9':
				saw_digits = true
				if c == '0' {
					if nd == 0 {
						decimal_point -= 1
						continue loop
					}
					if trailing_zeroes_nd == -1 {
						trailing_zeroes_nd = nd
					}
				} else {
					trailing_zeroes_nd = -1
				}

				nd += 1
				if nd_mant < MAX_MANT_DIGITS {
					mantissa *= base
					mantissa += u64(c - '0')
					nd_mant += 1
				} else if c != '0' {
					trunc = true
				}
				continue loop
			case base == 16 && 'a' <= lower(c) && lower(c) <= 'f':
				saw_digits = true
				nd += 1
				if nd_mant < MAX_MANT_DIGITS {
					mantissa *= 16
					mantissa += u64(lower(c) - 'a' + 10)
					nd_mant += 1
				} else {
					trunc = true
				}
				continue loop
			}
			break loop
		}

		if !saw_digits {
			return
		}
		if !saw_dot {
			decimal_point = nd
		}
		if trailing_zeroes_nd > 0 {
			trailing_zeroes_nd = nd_mant - trailing_zeroes_nd
		}
		for ; trailing_zeroes_nd > 0; trailing_zeroes_nd -= 1 {
			mantissa /= base
			nd_mant -= 1
			nd -= 1
		}
		if hex {
			decimal_point *= 4
			nd_mant *= 4
		}

		if i < len(s) && lower(s[i]) == exp_char {
			i += 1
			if i >= len(s) {
				return
			}
			exp_sign := 1
			switch s[i] {
			case '+': i += 1
			case '-': i += 1; exp_sign = -1
			}
			if i >= len(s) || s[i] < '0' || s[i] > '9' {
				return
			}

			e := 0
			for ; i < len(s) && ('0' <= s[i] && s[i] <= '9' || s[i] == '_'); i += 1 {
				if s[i] == '_' {
					continue
				}
				if e < 1e5 {
					e = e*10 + int(s[i]-'0')
				}
			}
			decimal_point += e * exp_sign
		} else if hex {
			return
		}

		if mantissa != 0 {
			exp = decimal_point - nd_mant
		}
		ok = true
		return
	}

	parse_hex :: proc "contextless" ($T: typeid, info: ^strconv.Float_Info, mantissa: u64, exp: int, neg, trunc: bool) -> (value: T, overflow: bool) {
		mantissa, exp := mantissa, exp

		MAX_EXP := 1<<info.expbits + info.bias - 2
		MIN_EXP := info.bias + 1
		exp += int(info.mantbits)

		for mantissa != 0 && mantissa >> (1+info.mantbits+2) == 0 {
			mantissa <<= 1
			exp -= 1
		}
		if trunc {
			mantissa |= 1
		}
		for mantissa >> (1+info.mantbits+2) != 0 {
			mantissa = mantissa>>1 | mantissa&1
			exp += 1
		}

		for mantissa > 1 && exp < MIN_EXP-2 {
			mantissa = mantissa>>1 | mantissa&1
			exp += 1
		}

		round := mantissa & 3
		mantissa >>= 2
		round |= mantissa & 1
		exp += 2
		if round == 3 {
			mantissa += 1
			if mantissa == 1 << (1 + info.mantbits) {
				mantissa >>= 1
				exp += 1
			}
		}
		if mantissa>>info.mantbits == 0 {
			exp = info.bias
		}

		if exp > MAX_EXP {
			mantissa = 1 << info.mantbits
			exp = MAX_EXP + 1
			overflow = true
		}

		bits := mantissa & (1<<info.mantbits - 1)
		bits |= u64((exp-info.bias) & (1<<info.expbits - 1)) << info.mantbits
		if neg {
			bits |= 1 << (info.mantbits+info.expbits)
		}
		return bits_to_float(T, bits), overflow
	}

	mantissa, exp, neg, trunc, hex, nr := parse_components(s) or_return
	assert(nr == len(s))
	if hex {
		return parse_hex(T, info, mantissa, exp, neg, trunc)
	}

	d: decimal.Decimal
	ok := decimal.set(&d, s)
	assert(ok)

	bits: u64
	bits, overflow = strconv.decimal_to_float_bits(&d, info)
	return bits_to_float(T, bits), overflow
}

tex_parse_f32 :: proc(s: string) -> (value: f32, overflow: bool) { return tex_parse_float(f32, s, &strconv._f32_info) }

tex_parse_f64 :: proc(s: string) -> (value: f64, overflow: bool) { return tex_parse_float(f64, s, &strconv._f64_info) }


@test
tex_parse_f32_test :: proc(t: ^testing.T) {
	tests := []struct {
		input:    string,
		bits:     u32,
		overflow: bool,
	}{
		{"1",                                       0x3f800000, false},
		{"-0",                                      0x80000000, false},
		{"1.000000059604644775390625",              0x3f800000, false},
		{"1.0000000596046447753906250000000000001", 0x3f800001, false},
		{"0x1p0",                                   0x3f800000, false},
		{"-0x1p0",                                  0xbf800000, false},
		{"0x1.fffffep127",                          0x7f7fffff, false},
		{"0x1p128",                                 0x7f800000, true},
		{"0x1p-149",                                0x00000001, false},
		{"0x1p-150",                                0x00000000, false},
		{"0x123456789abcdef0p0",                    0x5d91a2b4, false},
		{"0x1.0000010000000000p0",                  0x3f800000, false},
	}

	for test in tests {
		value, overflow := tex_parse_f32(test.input)
		testing.expect_value(t, transmute(u32)value, test.bits)
		testing.expect_value(t, overflow, test.overflow)
	}
}

@test
tex_parse_f64_test :: proc(t: ^testing.T) {
	tests := []struct {
		input:    string,
		bits:     u64,
		overflow: bool,
	}{
		{"1",                                                           0x3ff0000000000000, false},
		{"-0",                                                          0x8000000000000000, false},
		{"1.00000000000000011102230246251565404236316680908203125",     0x3ff0000000000000, false},
		{"1.000000000000000111022302462515654042363166809082031250001", 0x3ff0000000000001, false},
		{"0x1p0",                                                       0x3ff0000000000000, false},
		{"-0x1p0",                                                      0xbff0000000000000, false},
		{"0x1.fffffffffffffp1023",                                      0x7fefffffffffffff, false},
		{"0x1p1024",                                                    0x7ff0000000000000, true},
		{"0x1p-1074",                                                   0x0000000000000001, false},
		{"0x1p-1075",                                                   0x0000000000000000, false},
		{"0x123456789abcdef0p0",                                        0x43b23456789abcdf, false},
		{"0x1.0000000000000800p0",                                      0x3ff0000000000000, false},
	}

	for test in tests {
		value, overflow := tex_parse_f64(test.input)
		testing.expect_value(t, transmute(u64)value, test.bits)
		testing.expect_value(t, overflow, test.overflow)
	}
}
