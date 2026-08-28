package wasim

import "core:log"
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

tex_par_get_next_paren_kind :: proc(p: ^Tex_Parser) -> (kind: Tex_Token_Kind) {
	if p.current_token.kind == .Paren_Open {
		kind = p.peek_token.kind
	}
	return
}

tex_par_paren_kind_begin :: proc(p: ^Tex_Parser, kind: Tex_Token_Kind) -> (ok: bool) {
	if p.current_token.kind == .Paren_Open {
		if p.peek_token.kind == kind {
			tex_par_next_token(p)
			tex_par_next_token(p)
			ok = true
		} else {
			tex_par_errorf_peek(p, "expected %v but only got %v", kind, p.current_token.kind)
			tex_par_attempt_recovery(p)
		}
	} else {
		tex_par_errorf_current(p, "expected '(' but only got %v", p.current_token.kind)
	}

	return
}

tex_par_paren_kind_end :: proc(p: ^Tex_Parser) {
	if tex_par_expect_current(p, .Paren_Close) {
		tex_par_next_token(p)
	} else {
		tex_par_attempt_recovery(p)
	}
}

tex_par_iterate_current_until :: proc(p: ^Tex_Parser, until: Tex_Token_Kind) -> bool {
	return p.current_token.kind != .Eof && p.current_token.kind != until
}

tex_par_attempt_recovery :: proc(p: ^Tex_Parser) {
	depth := 0
	for p.current_token.kind != .Eof {
		if depth < 0 {
			break
		}

		#partial switch p.current_token.kind {
		case .Paren_Open:  depth += 1
		case .Paren_Close:
			depth -= 1
		}

		tex_par_next_token(p)
	}
}

tex_par_parse_id :: proc(p: ^Tex_Parser) -> (id: string) {
	if p.current_token.kind == .Identifier {
		id = p.current_token.data
		tex_par_next_token(p)
	}
	return
}

tex_par_parse_module :: proc(p: ^Tex_Parser, arena: ^B.Arena) -> (module: ^Tex_Module) {
	p.arena = arena

	module = B.arena_push(p.arena, Tex_Module)

	module.range.start = p.current_token
	if tex_par_paren_kind_begin(p, .Module) {
		module.id = tex_par_parse_id(p)

		loop: for {
			#partial switch p.current_token.kind {
			case .Paren_Open:
				#partial switch p.peek_token.kind {
				case .Func:
					list_push(&module.funcs, tex_par_parse_func(p))
				case:
					tex_par_errorf_peek(p, "invalid module field %v", p.peek_token.kind)
				}
			case: break loop
			}
		}

		module.range.end = p.current_token
		tex_par_paren_kind_end(p)
		tex_par_expect_current(p, .Eof)
	}

	return
}

tex_par_parse_named_value_type :: proc(p: ^Tex_Parser, keyword: Tex_Token_Kind) -> (named_value_types: List(Tex_Named_Value_Type)) {
	for tex_par_get_next_paren_kind(p) == keyword {
		if tex_par_paren_kind_begin(p, keyword) {
			named: Tex_Named_Value_Type

			if p.current_token.kind == .Identifier {
				named.id = p.current_token.data
				tex_par_next_token(p)
			}

			if p.current_token.kind != .Paren_Close {
				named.value_type = tex_par_parse_value_type(p)
				list_push(&named_value_types, B.arena_push(p.arena, named))

				if named.id == "" {
					for tex_par_iterate_current_until(p, .Paren_Close) {
						named.value_type = tex_par_parse_value_type(p)
						list_push(&named_value_types, B.arena_push(p.arena, named))
					}
				}
			}

			tex_par_paren_kind_end(p)
		}
	}

	return
}

tex_par_parse_value_types :: proc(p: ^Tex_Parser, keyword: Tex_Token_Kind) -> (value_types: List(Tex_Value_Type_Node)) {
	for tex_par_get_next_paren_kind(p) == keyword {
		if tex_par_paren_kind_begin(p, keyword) {
			result: Tex_Value_Type_Node

			for tex_par_iterate_current_until(p, .Paren_Close) {
				result.value_type = tex_par_parse_value_type(p)
				list_push(&value_types, B.arena_push(p.arena, result))
			}

			tex_par_paren_kind_end(p)
		}
	}

	return
}

tex_par_parse_func_type_decl :: proc(p: ^Tex_Parser) -> (func_type: Tex_Func_Type) {
	func_type.params = tex_par_parse_named_value_type(p, .Param)
	func_type.results = tex_par_parse_value_types(p, .Result)

	return
}

tex_par_parse_func :: proc(p: ^Tex_Parser) -> (func: ^Tex_Func) {
	assert(p.current_token.kind == .Paren_Open)
	assert(p.peek_token.kind == .Func)
	func = B.arena_push(p.arena, Tex_Func)

	func.range.start = p.current_token
	if tex_par_paren_kind_begin(p, .Func) {
		func.id = tex_par_parse_id(p)

		if tex_par_get_next_paren_kind(p) == .Type {
			assert(tex_par_paren_kind_begin(p, .Type))

			#partial switch p.current_token.kind {
			case .Identifier:
				func.use.id = p.current_token.data
			case .Integer_Unsigned:
				err: Tex_Integer_Conversion_Error
				func.use.index, err = tex_u32_from_string(p.current_token.data)
				switch err {
				case .Number_To_Large:
					tex_par_errorf_current(p, "integer %q does not fit into an u32", p.current_token.data)
				case .None, .Number_To_Small: // NOTE(robin): Number_To_Small can't happen for Unsigned_Integers
				}
			}

			tex_par_next_token(p)

			func.use.inlined_type = tex_par_parse_func_type_decl(p)

			tex_par_paren_kind_end(p)
		}

		func.locals = tex_par_parse_named_value_type(p, .Local)

		func.range.end = p.current_token
		tex_par_paren_kind_end(p)
	}

	return
}

import "core:testing"

@private
tex_par_test_parser :: proc(input: string, par_error_proc := tex_par_test_error_log, tok_error_proc := tex_tok_test_error_log) -> (p: Tex_Parser) {
	tok: Tex_Tokenizer
	tex_tok_init(&tok, input, "test.wat", tok_error_proc)
	tex_par_init(&p, tok, par_error_proc)

	return
}

@private
tex_par_test_funcs :: proc(arena: ^B.Arena, funcs: ..Tex_Func) -> (l: List(Tex_Func)) {
	for func in funcs {
		node := B.arena_push(arena, Tex_Func)
		node^ = func
		list_push(&l, node)
	}

	return
}

@private
tex_par_test_expect_list_equal :: proc(t: ^testing.T, value, expected: List($T), equal: proc(a, b: T) -> bool) {
	if value.count != expected.count {
		log.errorf("expected %v entries in list, found %v", expected.count, value.count)
	}

	small := min(value.count, expected.count)

	value_current    := value.first
	expected_current := expected.first

	for i in 0..<small {
		if !equal(value_current^, expected_current^) {
			log.errorf("entry %v does not match with expected, entry=%v, expected=%v", i, value_current^, expected_current^)
		}

		value_current    = value_current.next
		expected_current = expected_current.next
	}
}

@private
tex_par_test_error_log :: proc(_: Tex_Token, format: string, args: ..any) {
	log.errorf(format, ..args)
}

@test
tex_par_parse_module_test :: proc(t: ^testing.T) {
	temp := B.TEMP_ALLOCATOR_GUARD()

	tests := []struct{input: string, module: Tex_Module}{
		{ "(module)", {} },
		{ "(module $hello)", { id = "$hello" } },
		{ "(module (func) (func $f))", { funcs = tex_par_test_funcs(temp, {}, { id = "$f" }) } },
		{ "(module (func (type 1)) (func (type $hello)))", { funcs = tex_par_test_funcs(temp, { use = { index = 1 } }, { use = { id = "$hello" } }) } },
	}

	for test in tests {
		p      := tex_par_test_parser(test.input)
		module := tex_par_parse_module(&p, temp)

		testing.expect(t, module != nil)
		testing.expect_value(t, module.id, test.module.id)
		testing.expect_value(t, p.errors, 0)

		tex_par_test_expect_list_equal(
			t,
			module.funcs,
			test.module.funcs,
			proc(a, b: Tex_Func) -> bool {
				return a.id == b.id && a.use == b.use
			},
		)
	}
}

@private
named_value_value_type :: proc(value_type: Value_Type) -> Tex_Named_Value_Type {
	return {
		value_type = value_type,
	}
}

@private
named_value_type :: proc{
	named_value_value_type,
}

@private
named_value_types_full :: proc(arena: ^B.Arena, named_value_types: ..Tex_Named_Value_Type) -> (l: List(Tex_Named_Value_Type)) {
	for named in named_value_types {
		node  := B.arena_push(arena, Tex_Named_Value_Type)
		node^  = named
		list_push(&l, node)
	}

	return
}

@private
named_value_types_simple :: proc(arena: ^B.Arena, named_value_types: ..Value_Type) -> (l: List(Tex_Named_Value_Type)) {
	for named in named_value_types {
		node            := B.arena_push(arena, Tex_Named_Value_Type)
		node.value_type  = named
		list_push(&l, node)
	}

	return
}

@private
value_types :: proc(arena: ^B.Arena, results: ..Value_Type) -> (l: List(Tex_Value_Type_Node)) {
	for result in results {
		node             := B.arena_push(arena, Tex_Value_Type_Node)
		node^.value_type  = result
		list_push(&l, node)
	}

	return
}

@test
tex_par_parse_named_value_types_test :: proc(t: ^testing.T) {
	temp := B.TEMP_ALLOCATOR_GUARD()

	tests := []struct{input: string, named_value_types: List(Tex_Named_Value_Type)}{
		{"(local)", {}},
		{"(local i32)", named_value_types_simple(temp, .I32)},
		{"(local i32 i64) (local f32 f64)", named_value_types_simple(temp, .I32, .I64, .F32, .F64)},
		{"(local $hello i32)", named_value_types_full(temp, { id = "$hello", value_type = .I32 })},
	}

	for test in tests {
		p                 := tex_par_test_parser(test.input)
		p.arena            = temp
		named_value_types := tex_par_parse_named_value_type(&p, .Local)

		tex_par_test_expect_list_equal(
			t,
			named_value_types,
			test.named_value_types,
			proc(a, b: Tex_Named_Value_Type) -> bool { return a.id == b.id && a.value_type == b.value_type },
		)
	}
}

@test
tex_par_parse_func_type_decl_test_valid :: proc(t: ^testing.T) {
	temp := B.TEMP_ALLOCATOR_GUARD()

	tests := []struct{input: string, func_type: Tex_Func_Type}{
		{"(param i32 i32 i32) (result i32 i32)", {named_value_types_simple(temp, .I32, .I32, .I32), value_types(temp, .I32, .I32)}},
		{"(param $hello i32) (result)", {named_value_types_full(temp, {id = "$hello", value_type = .I32}), value_types(temp)}},
		{"(param $hello i32) (param $world f64) (result)", {named_value_types_full(temp, {id = "$hello", value_type = .I32}, {id = "$world", value_type = .F64}), value_types(temp)}},
		{"(param) (result)", {}},
	}

	for test in tests {
		p         := tex_par_test_parser(test.input)
		p.arena    = temp
		func_type := tex_par_parse_func_type_decl(&p)

		testing.expect_value(t, p.errors, 0)
		testing.expect_value(t, func_type.params.count, test.func_type.params.count)
		testing.expect_value(t, func_type.results.count, test.func_type.results.count)
	}
}

@test
tex_par_parse_func_type_decl_test_invalid :: proc(t: ^testing.T) {
	temp := B.TEMP_ALLOCATOR_GUARD()

	tests := []struct{input: string, errors: int}{
		{"(result $hi i32)", 1},
		{"(result", 1},
		{"(param f16)", 1},
	}

	for test in tests {
		p         := tex_par_test_parser(test.input, nil, nil)
		p.arena    = temp
		_ = tex_par_parse_func_type_decl(&p)

		testing.expect_value(t, p.errors, test.errors)
	}
}
