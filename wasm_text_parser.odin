package wasim

import "core:fmt"

import B "base"

Tex_Par_Error_Proc :: #type proc(token: Tex_Token, format: string, args: ..any)

tex_par_default_error_proc : Tex_Par_Error_Proc : proc(token: Tex_Token, format: string, args: ..any) {
	fmt.eprintf("%v:%v:%v: Parser Error: ", token.file, token.row, token.col)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
}

Tex_Parser :: struct {
	arena: ^B.Arena,

	tokenizer: Tex_Tokenizer,

	current_token: Tex_Token,
	peek_token:    Tex_Token,

	error_proc: Tex_Par_Error_Proc,
	errors:     int,
}

tex_par_init :: proc(p: ^Tex_Parser, tokenizer: Tex_Tokenizer, error_proc := tex_par_default_error_proc) {
	p^ = {
		tokenizer = tokenizer,

		error_proc = error_proc,
	}

	tex_par_next_token(p)
	tex_par_next_token(p)
}

tex_par_errorf :: proc(p: ^Tex_Parser, token: Tex_Token, format: string, args: ..any) {
	if p.error_proc != nil {
		p.error_proc(token, format, ..args)
	}
	p.errors += 1
}

tex_par_errorf_current :: proc(p: ^Tex_Parser, format: string, args: ..any) {
	tex_par_errorf(p, p.current_token, format, ..args)
}

tex_par_errorf_peek :: proc(p: ^Tex_Parser, format: string, args: ..any) {
	tex_par_errorf(p, p.peek_token, format, ..args)
}

tex_par_next_token :: proc(p: ^Tex_Parser) {
	p.current_token = p.peek_token
	p.peek_token    = tex_tok_next(&p.tokenizer)
}

tex_par_expect_current :: proc(p: ^Tex_Parser, kind: Tex_Token_Kind) -> (ok: bool) {
	ok = p.current_token.kind == kind

	if !ok {
		tex_par_errorf_current(p, "expected %v, but got %v", kind, p.current_token.kind)
	}

	return
}

tex_par_expect_peek :: proc(p: ^Tex_Parser, kind: Tex_Token_Kind) -> (ok: bool) {
	ok = p.peek_token.kind == kind

	if !ok {
		tex_par_errorf_peek(p, "expected %v, but got %v", kind, p.peek_token.kind)
	}
	tex_par_next_token(p)

	return
}

tex_par_parse_value_type :: proc(p: ^Tex_Parser) -> (value_type: Value_Type) {
	#partial switch p.current_token.kind {
	case .I32: value_type = .I32
	case .I64: value_type = .I64
	case .F32: value_type = .F32
	case .F64: value_type = .F64
	case:
		tex_par_errorf_current(p, "invalid value type %q", p.current_token.data)
	}

	tex_par_next_token(p)

	return
}

tex_par_parse_module :: proc(p: ^Tex_Parser) -> (module: ^Tex_Module) {
	module = B.arena_push(p.arena, Tex_Module)

	if tex_par_expect_current(p, .Paren_Open) {
		module.range.start = p.current_token

		tex_par_expect_peek(p, .Module)
		tex_par_expect_peek(p, .Paren_Close)

		module.range.end = p.current_token

		tex_par_expect_peek(p, .Eof)
	}

	return
}

import "core:testing"

@test
tex_par_parse_module_test :: proc(t: ^testing.T) {

}
