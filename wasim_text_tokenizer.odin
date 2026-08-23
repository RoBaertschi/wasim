package wasim

import "core:fmt"
import "core:log"
import "core:strings"
import "core:unicode/utf8"

Tex_Position :: struct {
	pos:  int,
	col:  int,
	row:  int,
	file: string,
}

Tex_Tok_Error_Proc :: #type proc(position: Tex_Position, format: string, args: ..any)

Tex_Tokenizer :: struct {
	using position: Tex_Position,

	input:  string,
	ch:     rune,
	ch_len: int,

	errors:     int,
	error_proc: Tex_Tok_Error_Proc,
}

tex_tok_errorf :: proc(t: ^Tex_Tokenizer, position: Tex_Position, format: string, args: ..any) {
	if t.error_proc != nil {
		t.error_proc(position, format, ..args)
	}
	t.errors += 1
}

tex_tok_errorf_here :: proc(t: ^Tex_Tokenizer, format: string, args: ..any) {
	tex_tok_errorf(t, t.position, format, ..args)
}

tex_tok_default_error_proc : Tex_Tok_Error_Proc : proc(position: Tex_Position, format: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: Error: ", position.file, position.row, position.col)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

// #region Token_Kind

Tex_Token_Kind :: enum {
	Invalid,
	Eof,

	Paren_Open,
	Paren_Close,

	Integer_Signed,
	Integer_Unsigned,
	Float,
	String,
	Identifier,
	Align_Equal_Natural,
	Offset_Equal_Natural,

	// WARN: These have to be kept in sync with ./tools/perfect-hash/keywords.txt
	I32,
	I64,
	F32,
	F64,
	I32_Const,
	I64_Const,
	F32_Const,
	F64_Const,
	Funcref,
	Mut,
	Nop,
	Unreachable,
	Drop,
	Block,
	Loop,
	End,
	Br,
	Br_If,
	Br_Table,
	Return,
	If,
	Then,
	Else,
	Select,
	Call,
	Call_Indirect,
	Local_Get,
	Local_Set,
	Local_Tee,
	Global_Get,
	Global_Set,
	I32_Load,
	I64_Load,
	F32_Load,
	F64_Load,
	I32_Store,
	I64_Store,
	F32_Store,
	F64_Store,
	I32_Load8_S,
	I32_Load8_U,
	I32_Load16_S,
	I32_Load16_U,
	I64_Load8_S,
	I64_Load8_U,
	I64_Load16_S,
	I64_Load16_U,
	I64_Load32_S,
	I64_Load32_U,
	I32_Store8,
	I32_Store16,
	I64_Store8,
	I64_Store16,
	I64_Store32,
	I32_Clz,
	I32_Ctz,
	I32_Popcnt,
	I64_Clz,
	I64_Ctz,
	I64_Popcnt,
	F32_Neg,
	F32_Abs,
	F32_Sqrt,
	F32_Ceil,
	F32_Floor,
	F32_Trunc,
	F32_Nearest,
	F64_Neg,
	F64_Abs,
	F64_Sqrt,
	F64_Ceil,
	F64_Floor,
	F64_Trunc,
	F64_Nearest,
	I32_Add,
	I32_Sub,
	I32_Mul,
	I32_Div_S,
	I32_Div_U,
	I32_Rem_S,
	I32_Rem_U,
	I32_And,
	I32_Or,
	I32_Xor,
	I32_Shl,
	I32_Shr_S,
	I32_Shr_U,
	I32_Rotl,
	I32_Rotr,
	I64_Add,
	I64_Sub,
	I64_Mul,
	I64_Div_S,
	I64_Div_U,
	I64_Rem_S,
	I64_Rem_U,
	I64_And,
	I64_Or,
	I64_Xor,
	I64_Shl,
	I64_Shr_S,
	I64_Shr_U,
	I64_Rotl,
	I64_Rotr,
	F32_Add,
	F32_Sub,
	F32_Mul,
	F32_Div,
	F32_Min,
	F32_Max,
	F32_Copysign,
	F64_Add,
	F64_Sub,
	F64_Mul,
	F64_Div,
	F64_Min,
	F64_Max,
	F64_Copysign,
	I32_Eqz,
	I64_Eqz,
	I32_Eq,
	I32_Ne,
	I32_Lt_S,
	I32_Lt_U,
	I32_Le_S,
	I32_Le_U,
	I32_Gt_S,
	I32_Gt_U,
	I32_Ge_S,
	I32_Ge_U,
	I64_Eq,
	I64_Ne,
	I64_Lt_S,
	I64_Lt_U,
	I64_Le_S,
	I64_Le_U,
	I64_Gt_S,
	I64_Gt_U,
	I64_Ge_S,
	I64_Ge_U,
	F32_Eq,
	F32_Ne,
	F32_Lt,
	F32_Le,
	F32_Gt,
	F32_Ge,
	F64_Eq,
	F64_Ne,
	F64_Lt,
	F64_Le,
	F64_Gt,
	F64_Ge,
	I32_Wrap_I64,
	I64_Extend_I32_S,
	I64_Extend_I32_U,
	F32_Demote_F64,
	F64_Promote_F32,
	I32_Trunc_F32_S,
	I32_Trunc_F32_U,
	I32_Trunc_F64_S,
	I32_Trunc_F64_U,
	I64_Trunc_F32_S,
	I64_Trunc_F32_U,
	I64_Trunc_F64_S,
	I64_Trunc_F64_U,
	F32_Convert_I32_S,
	F32_Convert_I32_U,
	F32_Convert_I64_S,
	F32_Convert_I64_U,
	F64_Convert_I32_S,
	F64_Convert_I32_U,
	F64_Convert_I64_S,
	F64_Convert_I64_U,
	F32_Reinterpret_I32,
	F64_Reinterpret_I64,
	I32_Reinterpret_F32,
	I64_Reinterpret_F64,
	Memory_Size,
	Memory_Grow,
	Type,
	Func,
	Start,
	Param,
	Result,
	Local,
	Global,
	Table,
	Memory,
	Elem,
	Data,
	Offset,
	Import,
	Export,
	Module,

	Keywords_Begin = I32,
	Keywords_End   = Module,
}

// #endregion

// #region tex_instruction_opcode_by_token_kind

// Non-instruction token kinds map to Instruction_Opcode.Invalid.
tex_instruction_opcode_by_token_kind := [Tex_Token_Kind]Instruction_Opcode{
	.Invalid = .Invalid,
	.Eof = .Invalid,
	.Paren_Open = .Invalid,
	.Paren_Close = .Invalid,
	.Integer_Signed = .Invalid,
	.Integer_Unsigned = .Invalid,
	.Float = .Invalid,
	.String = .Invalid,
	.Identifier = .Invalid,
	.Align_Equal_Natural = .Invalid,
	.Offset_Equal_Natural = .Invalid,
	.I32 = .Invalid,
	.I64 = .Invalid,
	.F32 = .Invalid,
	.F64 = .Invalid,
	.I32_Const = .I32_Const,
	.I64_Const = .I64_Const,
	.F32_Const = .F32_Const,
	.F64_Const = .F64_Const,
	.Funcref = .Invalid,
	.Mut = .Invalid,
	.Nop = .Nop,
	.Unreachable = .Unreachable,
	.Drop = .Drop,
	.Block = .Block,
	.Loop = .Loop,
	.End = .End,
	.Br = .Br,
	.Br_If = .Br_If,
	.Br_Table = .Br_Table,
	.Return = .Return,
	.If = .If,
	.Then = .Invalid,
	.Else = .Else,
	.Select = .Select,
	.Call = .Call,
	.Call_Indirect = .Call_Indirect,
	.Local_Get = .Local_Get,
	.Local_Set = .Local_Set,
	.Local_Tee = .Local_Tee,
	.Global_Get = .Global_Get,
	.Global_Set = .Global_Set,
	.I32_Load = .I32_Load,
	.I64_Load = .I64_Load,
	.F32_Load = .F32_Load,
	.F64_Load = .F64_Load,
	.I32_Store = .I32_Store,
	.I64_Store = .I64_Store,
	.F32_Store = .F32_Store,
	.F64_Store = .F64_Store,
	.I32_Load8_S = .I32_Load8_s,
	.I32_Load8_U = .I32_Load8_u,
	.I32_Load16_S = .I32_Load16_s,
	.I32_Load16_U = .I32_Load16_u,
	.I64_Load8_S = .I64_Load8_s,
	.I64_Load8_U = .I64_Load8_u,
	.I64_Load16_S = .I64_Load16_s,
	.I64_Load16_U = .I64_Load16_u,
	.I64_Load32_S = .I64_Load32_s,
	.I64_Load32_U = .I64_Load32_u,
	.I32_Store8 = .I32_Store8,
	.I32_Store16 = .I32_Store16,
	.I64_Store8 = .I64_Store8,
	.I64_Store16 = .I64_Store16,
	.I64_Store32 = .I64_Store32,
	.I32_Clz = .I32_Clz,
	.I32_Ctz = .I32_Ctz,
	.I32_Popcnt = .I32_Popcnt,
	.I64_Clz = .I64_Clz,
	.I64_Ctz = .I64_Ctz,
	.I64_Popcnt = .I64_Popcnt,
	.F32_Neg = .F32_Neg,
	.F32_Abs = .F32_Abs,
	.F32_Sqrt = .F32_Sqrt,
	.F32_Ceil = .F32_Ceil,
	.F32_Floor = .F32_Floor,
	.F32_Trunc = .F32_Trunc,
	.F32_Nearest = .F32_Nearest,
	.F64_Neg = .F64_Neg,
	.F64_Abs = .F64_Abs,
	.F64_Sqrt = .F64_Sqrt,
	.F64_Ceil = .F64_Ceil,
	.F64_Floor = .F64_Floor,
	.F64_Trunc = .F64_Trunc,
	.F64_Nearest = .F64_Nearest,
	.I32_Add = .I32_Add,
	.I32_Sub = .I32_Sub,
	.I32_Mul = .I32_Mul,
	.I32_Div_S = .I32_Div_s,
	.I32_Div_U = .I32_Div_u,
	.I32_Rem_S = .I32_Rem_s,
	.I32_Rem_U = .I32_Rem_u,
	.I32_And = .I32_And,
	.I32_Or = .I32_Or,
	.I32_Xor = .I32_Xor,
	.I32_Shl = .I32_Shl,
	.I32_Shr_S = .I32_Shr_s,
	.I32_Shr_U = .I32_Shr_u,
	.I32_Rotl = .I32_Rotl,
	.I32_Rotr = .I32_Rotr,
	.I64_Add = .I64_Add,
	.I64_Sub = .I64_Sub,
	.I64_Mul = .I64_Mul,
	.I64_Div_S = .I64_Div_s,
	.I64_Div_U = .I64_Div_u,
	.I64_Rem_S = .I64_Rem_s,
	.I64_Rem_U = .I64_Rem_u,
	.I64_And = .I64_And,
	.I64_Or = .I64_Or,
	.I64_Xor = .I64_Xor,
	.I64_Shl = .I64_Shl,
	.I64_Shr_S = .I64_Shr_s,
	.I64_Shr_U = .I64_Shr_u,
	.I64_Rotl = .I64_Rotl,
	.I64_Rotr = .I64_Rotr,
	.F32_Add = .F32_Add,
	.F32_Sub = .F32_Sub,
	.F32_Mul = .F32_Mul,
	.F32_Div = .F32_Div,
	.F32_Min = .F32_Min,
	.F32_Max = .F32_Max,
	.F32_Copysign = .F32_Copysign,
	.F64_Add = .F64_Add,
	.F64_Sub = .F64_Sub,
	.F64_Mul = .F64_Mul,
	.F64_Div = .F64_Div,
	.F64_Min = .F64_Min,
	.F64_Max = .F64_Max,
	.F64_Copysign = .F64_Copysign,
	.I32_Eqz = .I32_Eqz,
	.I64_Eqz = .I64_Eqz,
	.I32_Eq = .I32_Eq,
	.I32_Ne = .I32_Ne,
	.I32_Lt_S = .I32_Lt_s,
	.I32_Lt_U = .I32_Lt_u,
	.I32_Le_S = .I32_Le_s,
	.I32_Le_U = .I32_Le_u,
	.I32_Gt_S = .I32_Gt_s,
	.I32_Gt_U = .I32_Gt_u,
	.I32_Ge_S = .I32_Ge_s,
	.I32_Ge_U = .I32_Ge_u,
	.I64_Eq = .I64_Eq,
	.I64_Ne = .I64_Ne,
	.I64_Lt_S = .I64_Lt_s,
	.I64_Lt_U = .I64_Lt_u,
	.I64_Le_S = .I64_Le_s,
	.I64_Le_U = .I64_Le_u,
	.I64_Gt_S = .I64_Gt_s,
	.I64_Gt_U = .I64_Gt_u,
	.I64_Ge_S = .I64_Ge_s,
	.I64_Ge_U = .I64_Ge_u,
	.F32_Eq = .F32_Eq,
	.F32_Ne = .F32_Ne,
	.F32_Lt = .F32_Lt,
	.F32_Le = .F32_Le,
	.F32_Gt = .F32_Gt,
	.F32_Ge = .F32_Ge,
	.F64_Eq = .F64_Eq,
	.F64_Ne = .F64_Ne,
	.F64_Lt = .F64_Lt,
	.F64_Le = .F64_Le,
	.F64_Gt = .F64_Gt,
	.F64_Ge = .F64_Ge,
	.I32_Wrap_I64 = .I32_Wrap_I64,
	.I64_Extend_I32_S = .I64_Extend_I32_s,
	.I64_Extend_I32_U = .I64_Extend_I32_u,
	.F32_Demote_F64 = .F32_Demote_F64,
	.F64_Promote_F32 = .F64_Promote_F32,
	.I32_Trunc_F32_S = .I32_Trunc_F32_s,
	.I32_Trunc_F32_U = .I32_Trunc_F32_u,
	.I32_Trunc_F64_S = .I32_Trunc_F64_s,
	.I32_Trunc_F64_U = .I32_Trunc_F64_u,
	.I64_Trunc_F32_S = .I64_Trunc_F32_s,
	.I64_Trunc_F32_U = .I64_Trunc_F32_u,
	.I64_Trunc_F64_S = .I64_Trunc_F64_s,
	.I64_Trunc_F64_U = .I64_Trunc_F64_u,
	.F32_Convert_I32_S = .F32_Convert_I32_s,
	.F32_Convert_I32_U = .F32_Convert_I32_u,
	.F32_Convert_I64_S = .F32_Convert_I64_s,
	.F32_Convert_I64_U = .F32_Convert_I64_u,
	.F64_Convert_I32_S = .F64_Convert_I32_s,
	.F64_Convert_I32_U = .F64_Convert_I32_u,
	.F64_Convert_I64_S = .F64_Convert_I64_s,
	.F64_Convert_I64_U = .F64_Convert_I64_u,
	.F32_Reinterpret_I32 = .F32_Reinterpret_I32,
	.F64_Reinterpret_I64 = .F64_Reinterpret_I64,
	.I32_Reinterpret_F32 = .I32_Reinterpret_F32,
	.I64_Reinterpret_F64 = .I64_Reinterpret_F64,
	.Memory_Size = .Memory_Size,
	.Memory_Grow = .Memory_Grow,
	.Type = .Invalid,
	.Func = .Invalid,
	.Start = .Invalid,
	.Param = .Invalid,
	.Result = .Invalid,
	.Local = .Invalid,
	.Global = .Invalid,
	.Table = .Invalid,
	.Memory = .Invalid,
	.Elem = .Invalid,
	.Data = .Invalid,
	.Offset = .Invalid,
	.Import = .Invalid,
	.Export = .Invalid,
	.Module = .Invalid,
}

// #endregion

Token :: struct {
	using position: Tex_Position,
	kind: Tex_Token_Kind,
	data: string,
}

tex_tok_init :: proc(t: ^Tex_Tokenizer, input: string, file: string, error_proc := tex_tok_default_error_proc) {
	t^ = {
		input = input,
		file  = file,
		row   = 1,

		error_proc = error_proc,
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
			tex_tok_errorf_here(t, "invalid utf-8 %v", t.input[t.pos])
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

tex_tok_is_reserved :: proc(s: string) -> (valid: bool) {
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
					tex_tok_errorf_here(t, "expected '{' after unicode escape in string, got %q instead", t.ch)
					continue
				}

				tex_tok_read_ch(t) // eat {

				if !tex_tok_is_digit(t.ch, 16) {
					token.kind = .Invalid
					tex_tok_errorf_here(t, "expected an hex number inside unicode escape in string, got %q instead", t.ch)
					continue
				}

				for tex_tok_is_digit(t.ch, 16) {
					tex_tok_read_ch(t) // eat digit
				}

				if t.ch != '}' {
					token.kind = .Invalid
					tex_tok_errorf_here(t, "expected '}' after hex number inside unicode escape in string, got %q instead", t.ch)
					continue
				}

				tex_tok_read_ch(t) // eat }
				continue
			case: // invalid escape sequence
				token.kind = .Invalid
				tex_tok_errorf_here(t, "invalid escape sequence character %q", t.ch)
			}

			continue
		case 0..<0x20: // control character
			token.kind = .Invalid
			tex_tok_errorf_here(t, "invalid control character %q in string", t.ch)
		case 0x7F: // delete control character
			token.kind = .Invalid
			tex_tok_errorf_here(t, "invalid control character %q in string", t.ch)
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

tex_tok_read_number_like :: proc(s: string) -> (kind: Tex_Token_Kind) {
	read_sign :: proc(s: ^string) -> (had_sign: bool) {
		if len(s) > 0 && (s[0] == '+' || s[0] == '-') {
			s^       = s[1:]
			had_sign = true
		}
		return
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

	read_regular :: proc(s: ^string, had_sign: bool) -> (kind: Tex_Token_Kind) {
		base := 10
		if strings.starts_with(s^, "0x") {
			base = 16
			s^ = s[2:]
		}

		digits_valid := read_digits(s, base)

		if digits_valid {
			if len(s) == 0 {
				kind = .Integer_Signed if had_sign else .Integer_Unsigned
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
	had_sign := read_sign(&rest)
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
			kind = read_regular(&rest, had_sign)
		}
	}
	return
}

tex_tok_read_memory_argument :: proc(s: string) -> (kind: Tex_Token_Kind) {
	for memory_argument in ([]struct {
		prefix: string,
		kind:   Tex_Token_Kind,
	}{
		{"align=",  .Align_Equal_Natural},
		{"offset=", .Offset_Equal_Natural},
	}) {
		if !strings.starts_with(s, memory_argument.prefix) {
			continue
		}

		natural := s[len(memory_argument.prefix):]
		if tex_tok_read_number_like(natural) == .Integer_Unsigned {
			return memory_argument.kind
		}
		break
	}

	return .Invalid
}

tex_tok_is_identifier :: proc(s: string) -> (valid: bool) {
	if strings.starts_with(s, "$") {
		i := 0
		for r in s {
			if !tex_tok_is_id_char(r) {
				break
			}
			i += 1
		}

		if i == len(s) && 2 <= len(s) { // is token fully matched and at least one id char after the $
			valid = true
		}
	}

	return
}

tex_tok_next :: proc(t: ^Tex_Tokenizer) -> (token: Token) {
	tex_tok_skip_space(t)

	token.position = t.position
	token.data     = t.input[t.pos:t.pos+t.ch_len]

	switch ch := t.ch; ch {
	case utf8.RUNE_EOF: token.kind = .Eof
	case '(':           token.kind = .Paren_Open
	case ')':           token.kind = .Paren_Close
	case '"': // string
		return tex_tok_read_string(t)
	case:
		// find full token
		tex_tok_skip_to_token_boundary(t)

		// slice input from token start to before boundary
		token.data = t.input[token.pos:t.pos]

		// in theory, a memory argument is a keyword, in reality, this is stupid
		token.kind = tex_tok_read_memory_argument(token.data)
		if token.kind != .Invalid {
			return
		}

		// NOTE(robin): spec is a bit fucked up about tokens
		//              it uses the longest match rule, so we
		//              conceptually need to apply each rule
		//              to see which one fits the longest

		// try number first (nan, inf could interfere with other)
		token.kind = tex_tok_read_number_like(token.data)
		if token.kind != .Invalid {
			return
		}

		index := tex_tok_perfect_hash_proc(token.data)

		if 0 <= index {
			// valid keyword
			token.kind = Tex_Token_Kind(int(Tex_Token_Kind.Keywords_Begin) + index)
			assert(.Keywords_Begin <= token.kind)
			assert(token.kind      <= .Keywords_End)

			return
		}

		if tex_tok_is_identifier(token.data) {
			// identifier
			token.kind = .Identifier
			return
		}


		is_reserved_token := tex_tok_is_reserved(token.data)

		if is_reserved_token {
			tex_tok_errorf(t, token.position, "found invalid reserved token %q", token.data)
		} else {
			tex_tok_errorf(t, token.position, "invalid token %q", token.data)
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
tex_tok_is_reserved_test_valid :: proc(t: ^testing.T) {
	valid_reserved_tokens := []string{
		"0123456789",
		"abcdefghijklmnopqrstuvwxyz",
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ",
		"!#$%&'*+-./:<=>?@\\^_`|~",
	}

	for valid in valid_reserved_tokens {
		testing.expect(t, tex_tok_is_reserved(valid))
	}
}

@test
tex_tok_is_reserved_test_invalid :: proc(t: ^testing.T) {
	invalid_reserved_token := []string{
		"   ",
		"öäü",
		"💀",
		"\"",
	}

	for invalid in invalid_reserved_token {
		testing.expect(t, !tex_tok_is_reserved(invalid))
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
		testing.expect_value(t, token.kind, Tex_Token_Kind.String)
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
		testing.expect_value(t, token.kind, Tex_Token_Kind.Invalid)
	}
}

@test
tex_tok_read_number_like_test_integer :: proc(t: ^testing.T) {
	valid_integers := []struct {
		input: string,
		kind:  Tex_Token_Kind,
	}{
		{"0",           .Integer_Unsigned},
		{"123",         .Integer_Unsigned},
		{"+123",        .Integer_Signed},
		{"-123",        .Integer_Signed},
		{"1_000_000",   .Integer_Unsigned},
		{"0x0",         .Integer_Unsigned},
		{"0xdead_BEEF", .Integer_Unsigned},
		{"+0x1234",     .Integer_Signed},
		{"-0x1_0000",   .Integer_Signed},
	}

	for valid in valid_integers {
		kind := tex_tok_read_number_like(valid.input)
		testing.expect_value(t, kind, valid.kind)
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
		testing.expect_value(t, kind, Tex_Token_Kind.Float)
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
		testing.expect_value(t, kind, Tex_Token_Kind.Invalid)
	}
}

@test
tex_tok_is_identifier_test_valid :: proc(t: ^testing.T) {
	valid_identifiers := []string{
		"$helloworld",
		"$$$$$$$$$$$$$$", // but why is this valid ????
		"$!#$%&'*+-./:<=>?@\\^_`|~",
		"$0123456789",
	}

	for valid in valid_identifiers {
		testing.expect(t, tex_tok_is_identifier(valid))
	}
}

@test
tex_tok_is_identifier_test_invalid :: proc(t: ^testing.T) {
	invalid_identifiers := []string{
		"helloworld",
		"$ ",
		"$\"",
		"$,",
		"$;",
		"${",
		"$}",
	}

	for invalid in invalid_identifiers {
		testing.expect(t, !tex_tok_is_identifier(invalid))
	}
}

@test
tex_tok_next_test :: proc(t: ^testing.T) {
	tests := []struct{
		input:  string,
		tokens: []Token,
	}{
		{ "(func)",              { { kind = .Paren_Open, data = "(" }, { kind = .Func, data = "func" }, { kind = .Paren_Close, data = ")" } } },
		{ "( func )",            { { kind = .Paren_Open, data = "(" }, { kind = .Func, data = "func" }, { kind = .Paren_Close, data = ")" } } },
		{ "align=4 offset=0x10", { { kind = .Align_Equal_Natural, data = "align=4" }, { kind = .Offset_Equal_Natural, data = "offset=0x10" } } },
		{ "align= 4",            { { kind = .Invalid, data = "align=" }, { kind = .Integer_Unsigned, data = "4" } } },
		{ "@",                   { { kind = .Invalid, data = "@" } } },
		{ " @@@$$ ",             { { kind = .Invalid, data = "@@@$$" } } },
	}

	for test in tests {
		tok: Tex_Tokenizer
		tex_tok_init(&tok, test.input, "test.wat")

		i := 0
		for token := tex_tok_next(&tok); token.kind != .Eof; token = tex_tok_next(&tok) {
			if len(test.tokens) <= i {
				log.errorf("tokenizer produced to many tokens, exepcted %v but got %v (current token=%v)", len(test.tokens), i, token)
			} else {
				testing.expect_value(t, token.kind, test.tokens[i].kind)
				testing.expect_value(t, token.data, test.tokens[i].data)
			}

			i += 1
		}
	}
}

@test
tex_tok_next_test_pos :: proc(t: ^testing.T) {
	tests := []struct{
		input:  string,
		tokens: []Token,
	}{
		{
			"(\nfunc)",
			{//             pos col row file
				{ position = { 0,  1,  1,  "" }, kind = .Paren_Open, data = "(" },
				{ position = { 2,  1,  2,  "" }, kind = .Func, data = "func" },
				{ position = { 6,  5,  2,  "" }, kind = .Paren_Close, data = ")" },
			},
		},
	}

	for test in tests {
		tok: Tex_Tokenizer
		tex_tok_init(&tok, test.input, "")

		i := 0
		for token := tex_tok_next(&tok); token.kind != .Eof; token = tex_tok_next(&tok) {
			if len(test.tokens) <= i {
				log.errorf("tokenizer produced to many tokens, exepcted %v but got %v (current token=%v)", len(test.tokens), i, token)
			} else {
				testing.expect_value(t, token.kind, test.tokens[i].kind)
				testing.expect_value(t, token.data, test.tokens[i].data)
				testing.expect_value(t, token.position, test.tokens[i].position)
			}

			i += 1
		}
	}
}
