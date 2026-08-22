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
				unimplemented()
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

tex_tok_read_number_like :: proc(s: string) -> (kind: Token_Kind) {
	s := s

	kind = .Integer

	if 0 < len(s) {
		switch s[0] {
		case '-', '+': s = s[1:]
		}
	}

	base := 10

	if strings.starts_with(s, "0x") {
		// hex mode
		base = 16
		s = s[2:]
	}

	if strings.starts_with(s, "_") {
		// TODO(robin): error
		kind = .Invalid
	}


	if kind != .Invalid {
		for r in s {
			if r == '_' {
			}
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

		switch ch {
		case 'a'..='z': // keyword
			index := tex_tok_perfect_hash_proc(token.data)
			if index < 0 {
				// invalid keyword
				// TODO(robin): error
			} else {
				// valid keyword
				token.kind = Token_Kind(int(Token_Kind.Keywords_Begin) + index)
				assert(.Keywords_Begin <= token.kind)
				assert(token.kind      <= .Keywords_End)
			}
		case '-', '+', '0'..='9': // number like
		case: // reserved
			// check if even a valid reserved token (which in itself is invalid)
			is_reserved_token := tex_tok_is_valid_reserved(token.data)
			_ = is_reserved_token
			// NOTE(robin): the error should probably mention if it is a reserved token or not
			// TODO(robin): error
		}

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
		"\"\\t\\n\\r\\\"\\'\\\\\"", // TODO(robin): test \u{...}
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
