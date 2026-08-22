package wasim

import "core:strings"
import "core:slice"
import "core:unicode/utf8"

Tex_Position :: struct {
	pos:  int,
	col:  int,
	row:  int,
	file: string,
}

Tex_Tokenizer :: struct {
	using position: Tex_Position,

	input:  string,
	ch:     rune,
	ch_len: int,
}

Token_Kind :: enum {
	Invalid,
	Eof,

	Paren_Open,
	Paren_Close,

	Integer,
	Float,
	String,
	Identifier,

	// WARN: These have to be kept in sync with ./tools/perfect-hash/keywords.txt
	Module,
	Func,

	Keywords_Begin = Module,
	Keywords_End   = Func,
}

Token :: struct {
	using position: Tex_Position,
	kind: Token_Kind,
	data: string,
}

tex_tok_init :: proc(t: ^Tex_Tokenizer, input: string, file: string) {
	t^ = {
		input = input,
		file  = file,
		row   = 1,
	}

	tex_tok_read_ch(t)
}

tex_tok_read_ch :: proc(t: ^Tex_Tokenizer) {
	if t.pos + t.ch_len >= len(t.input) {
		t.pos    = len(t.input)
		t.ch     = utf8.RUNE_EOF
		t.ch_len = 0
	} else {
		t.pos += t.ch_len

		if t.ch != '\n' {
			t.col += 1
		} else {
			t.row += 1
			t.col  = 1
		}

		t.ch, t.ch_len = utf8.decode_rune(t.input[t.pos:])
		if t.ch == utf8.RUNE_ERROR {
			// TODO(robin): handle error
		}
}
}

tex_tok_is_space :: #force_inline proc(ch: rune) -> bool {
	switch ch {
	case ' ', 0x09, 0x0A, 0x0D: return true
	case:                       return false
	}
}

tex_tok_is_id_char :: #force_inline proc(ch: rune) -> bool {
	switch ch {
	case '0'..='9',
			 'A'..='Z',
			 'a'..='z',
			 '!',  '#', '$',  '%', '&',
			 '\'', '*', '+',  '-', '.',
			 '/',  ':', '<',  '=', '>',
			 '?',  '@', '\\', '^', '_',
			 '`',  '|', '~':
		return true
	case:
		return false
	}
}

tex_tok_is_valid_reserved :: proc(s: string) -> (valid: bool) {
	valid = true
	for r in s {
		if !tex_tok_is_id_char(r) {
			valid = false
			break
		}
	}
	return
}

tex_tok_peek :: proc(t: ^Tex_Tokenizer) -> byte {
	if t.pos + t.ch_len >= len(t.input) {
		return 0
	} else {
		return t.input[t.pos+t.ch_len]
	}
}

// Skips white space and comments
tex_tok_skip_space :: proc(t: ^Tex_Tokenizer) {
	for {
		if tex_tok_is_space(t.ch) {
			tex_tok_read_ch(t)
			continue
		}

		switch t.ch {
		case utf8.RUNE_EOF: break
		case ';':
			if tex_tok_peek(t) == ';' {
				tex_tok_read_ch(t)
				tex_tok_read_ch(t)

				for t.ch != '\n' {
					tex_tok_read_ch(t)
				}

				continue
			}
		case '(':
			if tex_tok_peek(t) == ';' {
				tex_tok_read_ch(t)
				tex_tok_read_ch(t)

				depth := 1

				for 0 < depth {
					switch t.ch {
					case utf8.RUNE_EOF: break
					case '(':
						if tex_tok_peek(t) == ';' {
							depth += 1
							tex_tok_read_ch(t)
							tex_tok_read_ch(t)

							continue
						}
					case ';':
						if tex_tok_peek(t) == ')' {
							depth -= 1
							tex_tok_read_ch(t)
							tex_tok_read_ch(t)

							continue
						}
					}

					tex_tok_read_ch(t)
				}

				continue
			}
		}

		break
	}
}

// Find next token boundary to test against
// TODO(robin): vectorize this?
tex_tok_skip_to_token_boundary :: proc(t: ^Tex_Tokenizer) {
	loop: for {
		if tex_tok_is_space(t.ch) {
			break
		}

		switch t.ch {
		case utf8.RUNE_EOF, '(', ')':
			break loop
		}

		tex_tok_read_ch(t)
	}
}

// TODO(robin): figure out how to differentiate between the validating and the parsing
tex_tok_read_string :: proc(t: ^Tex_Tokenizer) -> (token: Token) {
	token.position = t.position
	token.kind = .String

	assert(t.ch == '"')
	tex_tok_read_ch(t)

	loop: for {
		switch t.ch {
		case utf8.RUNE_EOF:
			token.kind = .Invalid
			break loop
		case '"':
			break loop
		case '\\': // escape sequence
			tex_tok_read_ch(t)

			switch t.ch {
			case 't', 'n', 'r', '"', '\'', '\\': // valid escape sequence
				tex_tok_read_ch(t)
			case 'u': // unicode escape sequence
				tex_tok_read_ch(t)

				if t.ch != '{' {
					token.kind = .Invalid
					// TODO(robin): error
					continue
				}

				tex_tok_read_ch(t) // eat {

				if !tex_tok_is_digit(t.ch, 16) {
					token.kind = .Invalid
					// TODO(robin): error
					continue
				}

				for tex_tok_is_digit(t.ch, 16) {
					tex_tok_read_ch(t) // eat digit
				}

				if t.ch != '}' {
					token.kind = .Invalid
					// TODO(robin): error
					continue
				}

				tex_tok_read_ch(t) // eat }
				continue
			case: // invalid escape sequence
				token.kind = .Invalid
				// TODO(robin): error
			}

			continue
		case 0..<0x20: // control character
			token.kind = .Invalid
			// TODO(robin): error
		case 0x7F: // delete control character
			token.kind = .Invalid
			// TODO(robin): error
		}
		tex_tok_read_ch(t)
	}

	if t.ch == '"' {
		tex_tok_read_ch(t)
	}

	token.data = t.input[token.pos:t.pos]

	return
}

tex_tok_is_digit :: proc(ch: rune, base: int) -> (valid: bool) {
	switch ch {
	case '0'..='9': return true
	case 'a'..='f',
		   'A'..='F': return base == 16
	case:           return false
	}
}

tex_tok_read_number_like :: proc(s: string) -> (kind: Token_Kind) {
	read_sign :: proc(s: ^string) {
		if len(s) > 0 && (s[0] == '+' || s[0] == '-') {
			s^ = s[1:]
		}
	}

	starts_with_digit :: proc(s: ^string, base: int) -> (result: bool) {
		result = len(s) > 0 && tex_tok_is_digit(rune(s[0]), base)
		return
	}

	read_digits :: proc(s: ^string, base: int) -> (valid: bool) {
		valid = starts_with_digit(s, base)
		if valid {
			s^ = s[1:]
			for len(s) > 0 {
				if tex_tok_is_digit(rune(s[0]), base) {
					s^ = s[1:]
				} else if s[0] == '_' && len(s) > 1 && tex_tok_is_digit(rune(s[1]), base) {
					s^ = s[2:]
				} else {
					break
				}
			}
		}
		return
	}

	read_exponent :: proc(s: ^string, marker_lower, marker_upper: byte) -> (found, valid: bool) {
		found = len(s) > 0 && (s[0] == marker_lower || s[0] == marker_upper)
		if found {
			s^ = s[1:]
			read_sign(s)
			valid = read_digits(s, 10)
		}
		return
	}

	read_regular :: proc(s: ^string) -> (kind: Token_Kind) {
		base := 10
		if strings.starts_with(s^, "0x") {
			base = 16
			s^ = s[2:]
		}

		digits_valid := read_digits(s, base)

		if digits_valid {
			if len(s) == 0 {
				kind = .Integer
			} else {
				has_point := s[0] == '.'
				if has_point {
					s^ = s[1:]
					_ = read_digits(s, base)
				}

				has_exponent, exponent_valid := read_exponent(
					s,
					base == 10 ? 'e' : 'p',
					base == 10 ? 'E' : 'P',
				)

				consumed_all      := len(s) == 0
				valid_exponent    := !has_exponent || exponent_valid
				hex_has_exponent  := base == 10 || has_exponent
				is_float_notation := has_point || has_exponent
				if consumed_all && valid_exponent && hex_has_exponent && is_float_notation {
					kind = .Float
				}
			}
		}

		return
	}

	rest := s
	read_sign(&rest)
	if len(rest) > 0 {
		switch {
		case rest == "inf", rest == "nan":
			kind = .Float
		case strings.starts_with(rest, "nan:0x"):
			rest = rest[len("nan:0x"):]
			if read_digits(&rest, 16) && len(rest) == 0 {
				kind = .Float
			}
		case:
			kind = read_regular(&rest)
		}
	}
	return
}

tex_tok_next :: proc(t: ^Tex_Tokenizer) -> (token: Token) {
	tex_tok_skip_space(t)

	token.position = t.position
	token.data     = t.input[t.pos:t.pos+t.ch_len]

	switch ch := t.ch; ch {
	case utf8.RUNE_EOF: // TODO(robin): error
	case '(': token.kind = .Paren_Open
	case ')': token.kind = .Paren_Close
	case '"': // string
		return tex_tok_read_string(t)
	case:
		// find full token
		tex_tok_skip_to_token_boundary(t)

		// slice input from token start to before boundary
		token.data = t.input[token.pos:t.pos]

		// NOTE(robin): spec is a bit fucked up about tokens
		//              it uses the longest match rule, so we
		//              conceptually need to apply each rule
		//              to see which one fits the longest

		// try number first (nan, inf could interfere with other)
		token.kind = tex_tok_read_number_like(token.data)
		if token.kind != .Invalid {
			break
		}

		index := tex_tok_perfect_hash_proc(token.data)

		if 0 <= index {
			// valid keyword
			token.kind = Token_Kind(int(Token_Kind.Keywords_Begin) + index)
			assert(.Keywords_Begin <= token.kind)
			assert(token.kind      <= .Keywords_End)

			break
		}

		is_reserved_token := tex_tok_is_valid_reserved(token.data)
		_ = is_reserved_token
		// NOTE(robin): the error should probably mention if it is a reserved token or not
		// TODO(robin): error

		return
	}

	tex_tok_read_ch(t)

	return
}

// Tests

@require import "core:testing"

@test
tex_tok_skip_space_test :: proc(t: ^testing.T) {
	tests := []string{
		"z",
		";; line comment\n\nz",
		"(; hello \n world (; nested \n block \t \r ;) after first nesting, and now we are done ;) z",
	}

	for test in tests {
		tok: Tex_Tokenizer
		tex_tok_init(&tok, test, "test.wat")

		tex_tok_skip_space(&tok)

		testing.expect_value(t, tok.ch, 'z')
	}
}

@test
tex_tok_skip_to_token_boundary_test :: proc(t: ^testing.T) {
	tests := []struct{input: string, final_pos: int}{
		{ "abc ", 3 },
		{ "abc(", 3 },
		{ "ABC ", 3 },
		{ "000 ", 3 },
		{ "$$$ ", 3 },
		{ " (",   0 },
		{ "(",    0 },
		{ "",     0 },
	}

	for test in tests {
		tok: Tex_Tokenizer
		tex_tok_init(&tok, test.input, "test.wat")

		tex_tok_skip_to_token_boundary(&tok)

		testing.expect_value(t, tok.pos, test.final_pos)
	}
}

@test
tex_tok_is_valid_reserved_test_valid :: proc(t: ^testing.T) {
	valid_reserved_tokens := []string{
		"0123456789",
		"abcdefghijklmnopqrstuvwxyz",
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ",
		"!#$%&'*+-./:<=>?@\\^_`|~",
	}

	for valid in valid_reserved_tokens {
		testing.expect(t, tex_tok_is_valid_reserved(valid))
	}
}

@test
tex_tok_is_valid_reserved_test_invalid :: proc(t: ^testing.T) {
	invalid_reserved_token := []string{
		"   ",
		"öäü",
		"💀",
		"\"",
	}

	for invalid in invalid_reserved_token {
		testing.expect(t, !tex_tok_is_valid_reserved(invalid))
	}
}

@test
tex_tok_read_string_test_valid :: proc(t: ^testing.T) {
	valid_strings := []string{
		"\"hello world\"",
		"\"\\t\\n\\r\\\"\\'\\\\\\u{0189ABEFabef}\"", // TODO(robin): test \u{...}
	}

	for valid in valid_strings {
		tok: Tex_Tokenizer
		tex_tok_init(&tok, valid, "test.wat")
		token := tex_tok_read_string(&tok)
		testing.expect_value(t, token.data, valid)
		testing.expect_value(t, token.kind, Token_Kind.String)
	}
}

@test
tex_tok_read_string_test_invalid :: proc(t: ^testing.T) {
	valid_strings := []string{
		"\"",
		"\"\n\"",
		"\"\v\"",
		"\"\x7F", // TODO(robin): test \u{...}
	}

	for valid in valid_strings {
		tok: Tex_Tokenizer
		tex_tok_init(&tok, valid, "test.wat")
		token := tex_tok_read_string(&tok)
		testing.expect_value(t, token.kind, Token_Kind.Invalid)
	}
}

@test
tex_tok_read_number_like_test_integer :: proc(t: ^testing.T) {
	valid_integers := []string{
		"0",
		"123",
		"+123",
		"-123",
		"1_000_000",
		"0x0",
		"0xdead_BEEF",
		"+0x1234",
		"-0x1_0000",
	}

	for valid in valid_integers {
		kind := tex_tok_read_number_like(valid)
		testing.expect_value(t, kind, Token_Kind.Integer)
	}
}

@test
tex_tok_read_number_like_test_float :: proc(t: ^testing.T) {
	valid_floats := []string{
		"0.",
		"1.5",
		"+1.5",
		"-1.5",
		"1e3",
		"1.e+3",
		"1_0.2_5e-2",
		"0x1p0",
		"0x1.p+2",
		"0x1.8p-1",
		"inf",
		"+inf",
		"-inf",
		"nan",
		"+nan",
		"-nan",
		"nan:0x1",
		"+nan:0xabc_DEF",
	}

	for valid in valid_floats {
		kind := tex_tok_read_number_like(valid)
		testing.expect_value(t, kind, Token_Kind.Float)
	}
}

@test
tex_tok_read_number_like_test_invalid :: proc(t: ^testing.T) {
	invalid_numbers := []string{
		"",
		"+",
		"-",
		"_1",
		"1_",
		"1__0",
		"0x",
		"0x_1",
		"0x1_",
		".",
		".5",
		"1e",
		"1e+",
		"1e_2",
		"1e2_",
		"1p2",
		"0x1.",
		"0x1p",
		"0x1p+",
		"0x1p_2",
		"nan:0x",
		"nan:0x_1",
		"nan:0x1_",
		"NaN",
		"Infinity",
		"1.2.3",
	}

	for invalid in invalid_numbers {
		kind := tex_tok_read_number_like(invalid)
		testing.expect_value(t, kind, Token_Kind.Invalid)
	}
}
