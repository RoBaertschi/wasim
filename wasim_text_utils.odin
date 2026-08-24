package wasim

import "base:intrinsics"
import "core:fmt"
import "core:unicode/utf8"
import "core:log"
import "core:strings"
import B "base"

tex_integer_rune_value :: proc(r: rune) -> (i: int) {
	switch r {
	case '0'..='9': return int(r-'0')
	case 'a'..='f': return int(r-'a')+10
	case 'A'..='F': return int(r-'A')+10
	}

	@cold
	fail :: proc(r: rune) -> ! {
		fmt.panicf("unsupported rune in tex_integer_rune_value %q", r)
	}
	fail(r)
}

Tex_Integer_Conversion_Error :: enum {
	None,
	Number_To_Large,
	Number_To_Small,
}

tex_iXX_from_string :: proc($T: typeid, s: string) -> (value: T, err: Tex_Integer_Conversion_Error)
	where !intrinsics.type_is_unsigned(T) {
	s := s

	I :: T
	U :: intrinsics.type_integer_to_unsigned(T)

	assert(0 < len(s))

	sign := I(1)

	switch s[0] {
	case '+': s = s[1:]
	case '-': s = s[1:]; sign = -1
	}

	value_unsigned: U
	value_unsigned, err = tex_uXX_from_string(U, s)

	if err == .None {
		if sign == 1 {
			if transmute(U)max(I) < value_unsigned {
				err = .Number_To_Large
			}
		} else {
			if transmute(U)min(I) < value_unsigned {
				err = .Number_To_Small
			}
		}
	} else {
		// adjust error to sign
		if err == .Number_To_Large && sign == -1 {
			err = .Number_To_Small
		}
	}

	if err == .None {
		value = I(value_unsigned) * sign
	}

	return
}

tex_i32_from_string :: proc(s: string) -> (value: i32, err: Tex_Integer_Conversion_Error) { return tex_iXX_from_string(i32, s) }
tex_i64_from_string :: proc(s: string) -> (value: i64, err: Tex_Integer_Conversion_Error) { return tex_iXX_from_string(i64, s) }

tex_uXX_from_string :: proc($T: typeid, s: string) -> (value: T, err: Tex_Integer_Conversion_Error) where intrinsics.type_is_unsigned(T) {
	s := s

	assert(0 < len(s))

	base := T(10)

	if strings.starts_with(s, "0x") {
		s    = s[len("0x"):]
		base = 16
	}

	for r in s {
		overflow: bool
		value, overflow = intrinsics.overflow_mul(value, base)
		if overflow {
			err = .Number_To_Large
			break
		}

		value, overflow = intrinsics.overflow_add(value, T(tex_integer_rune_value(r)))
		if overflow {
			err = .Number_To_Large
			break
		}
	}

	return
}

tex_u32_from_string :: proc(s: string) -> (u32, Tex_Integer_Conversion_Error) { return tex_uXX_from_string(u32, s) }
tex_u64_from_string :: proc(s: string) -> (u64, Tex_Integer_Conversion_Error) { return tex_uXX_from_string(u64, s) }

// Quoted string

tex_valid_string :: utf8.valid_string

// NOTE: this could introduce invalid utf-8 into the string
// NOTE: allocation is not guaranteed
tex_unquote_string :: proc(quoted: string, arena: ^B.Arena) -> (unquoted: []byte) {
	assert(2 <= len(quoted))
	assert(quoted[0] == '"')
	assert(quoted[len(quoted)-1] == '"')

	s := quoted[1:len(quoted)-1]

	if strings.index_byte(quoted, '\\') == -1 { // no escape sequence found
		return transmute([]byte)s
	}

	unquoted = B.arena_push_make(arena, []byte, len(quoted))

	bytes_push_string :: proc(data: []byte, i: ^int, s: string) {
		i^ += copy(data[i^:i^+len(s)], s)
	}

	bytes_push_rune :: proc(data: []byte, i: ^int, r: rune) {
		rune_encoded, rune_len := utf8.encode_rune(r)
		i^ += copy(data[i^:i^+rune_len], rune_encoded[:rune_len])
	}

	bytes_push_byte :: proc(data: []byte, i: ^int, b: byte) {
		data[i^] = b
		i^ += 1
	}

	bytes_push :: proc{
		bytes_push_string,
		bytes_push_rune,
		bytes_push_byte,
	}

	advance :: proc(s: ^string, ch: ^rune, ch_len: ^int) {
		s^ = s[ch_len^:]
		ch^, ch_len^ = utf8.decode_rune(s^)
	}

	i: int
	ch: rune
	ch_len: int
	for 0 < len(s) {
		advance(&s, &ch, &ch_len)

		switch ch {
		case '\\':
			advance(&s, &ch, &ch_len)
			switch ch {
			case 't':  bytes_push(unquoted, &i, byte('\t'))
			case 'n':  bytes_push(unquoted, &i, byte('\n'))
			case 'r':  bytes_push(unquoted, &i, byte('\r'))
			case '"':  bytes_push(unquoted, &i, byte('\"'))
			case '\'': bytes_push(unquoted, &i, byte('\''))
			case '\\': bytes_push(unquoted, &i, byte('\\'))
			case 'u':
				unimplemented()
			case: // hex \hh
				first := tex_integer_rune_value(ch)
				advance(&s, &ch, &ch_len)
				second := tex_integer_rune_value(ch)
				bytes_push(unquoted, &i, 16*byte(first) + byte(second))
			}
		case: bytes_push(unquoted, &i, s[:ch_len])
		}
	}

	extra    := len(unquoted) - i
	unquoted  = unquoted[:i]
	B.arena_pop(arena, extra)

	return
}

import "core:testing"

@test
tex_unquote_string_test :: proc(t: ^testing.T) {
	byte_lit :: proc(s: string) -> []byte {
		return transmute([]byte)s
	}

	expect_bytes_equal :: proc(actual, expected: []byte) {
		if len(actual) != len(expected) {
			log.errorf("unquoted byte count mismatch: expected %v, got %v", len(expected), len(actual))
			return
		}

		for byte, i in actual {
			if byte != expected[i] {
				log.errorf("unquoted byte mismatch at index %v: expected %v, got %v", i, expected[i], byte)
			}
		}
	}

	tests := []struct{quoted: string, unquoted: []byte, utf8_valid: bool}{
		{"\"Hello World\"", byte_lit("Hello World"), true},
		{"\"\\t\"",         byte_lit("\t"), true},
		{"\"\\n\"",         byte_lit("\n"), true},
		{"\"\\r\"",         byte_lit("\r"), true},
		{"\"\\\"\"",        byte_lit("\""), true},
		{"\"\\\'\"",        byte_lit("\'"), true},
		{"\"\\\\\"",        byte_lit("\\"), true},
		{"\"\\c3\\a9\"",    {195, 169},     true},
		{"\"\\ff\"",        {255},          false},
	}

	temp := B.TEMP_ALLOCATOR_GUARD()

	for test in tests {
		unquoted := tex_unquote_string(test.quoted, temp)
		expect_bytes_equal(unquoted, test.unquoted)
		testing.expect_value(t, tex_valid_string(transmute(string)unquoted), test.utf8_valid)
	}
}

@test
tex_u32_from_string_test :: proc(t: ^testing.T) {
	tests := []struct{input: string, result: u32, err: Tex_Integer_Conversion_Error}{
		{ "0", 0, .None },
		{ "0x09", 9, .None },
		{ "4294967295", max(u32), .None },
		{ "4294967296", 0, .Number_To_Large },
	}

	for test in tests {
		result, err := tex_u32_from_string(test.input)
		if test.err != .None {
			testing.expect_value(t, result, test.result)
		}
		testing.expect_value(t, err, test.err)
	}
}

@test
tex_i32_from_string_test :: proc(t: ^testing.T) {
	tests := []struct{input: string, result: i32, err: Tex_Integer_Conversion_Error}{
		{ "0",            0,       .None },
		{ "-0",           0,       .None },
		{ "0x09",         9,       .None },
		{ "-0x09",       -9,       .None },
		{ "2147483647",  max(i32), .None },
		{ "2147483648",   0,       .Number_To_Large },
		{ "-2147483648", min(i32), .None },
		{ "-2147483649",  0,       .Number_To_Small },
	}

	for test in tests {
		result, err := tex_i32_from_string(test.input)
		if test.err != .None {
			testing.expect_value(t, result, test.result)
		}
		testing.expect_value(t, err, test.err)
	}
}
