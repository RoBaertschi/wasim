package c_gen

import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"
import "core:testing"
import "core:fmt"

parse_test_model :: proc(t: ^testing.T, source: string) -> Model {
	pkg := ast.new(ast.Package, tokenizer.Pos{}, tokenizer.Pos{})
	file := ast.new(ast.File, tokenizer.Pos{}, tokenizer.Pos{})
	file.src = source
	file.fullpath = "fixture.odin"
	file.pkg = pkg
	pkg.files[file.fullpath] = file
	p := parser.default_parser()
	if !parser.parse_file(&p, file) {
		testing.expect(t, false, "test fixture must parse")
		return {}
	}
	pkg.name = file.pkg_decl.name
	m := Model{pkg = pkg, prefix = c_prefix(pkg.name), func_prefix = pkg.name}
	collect(&m)
	validate(&m)
	return m
}

@test
annotation_and_wopt_signature :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	m := parse_test_model(t, `package fixture
@(tag="cabi") Flag :: enum { A, B }
@(tag="cabi") Flags :: bit_set[Flag]
@(tag="cabi") add :: proc(a, b: i32, values: ..i32, flags := Flags{}) -> i32 { return a }
@(link_name="unused", tag="cabi") tagged :: proc() {}
`)
	testing.expect_value(t, m.errors, 0)
	testing.expect_value(t, len(m.procs), 2)
	header := emit_header(&m)
	wrappers := emit_wrappers(&m)
	testing.expect(t, strings.contains(header, "typedef intptr_t Fixture_Flag;"))
	testing.expect(t, strings.contains(header, "typedef uint8_t Fixture_Flags;"))
	testing.expect(t, strings.contains(header, "int32_t a, int32_t b, Fixture_Slice_i32 values, Fixture_Flags flags"))
	testing.expect(t, strings.contains(wrappers, "flags = flags"))
}

@test
declaration_order_and_borrowed_records :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	m := parse_test_model(t, `package fixture
@(tag="cabi") Record :: struct { entries: []Entry, using entry: Entry }
@(tag="cabi") Entry :: struct { id: u32 }
@(tag="cabi") identity :: proc(record: Record) -> Record { return record }
`)
	testing.expect_value(t, m.errors, 0)
	header := emit_header(&m)
	testing.expect(t, strings.index(header, "struct Fixture_Entry {") < strings.index(header, "struct Fixture_Record {"))
	testing.expect(t, strings.index(header, "typedef struct Fixture_Slice_Entry") < strings.index(header, "struct Fixture_Record {"))
	testing.expect_value(t, m.errors, 0)
}

@test
unsupported_exports_are_errors :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sources := []string{
		`package fixture
@(tag="cabi") U :: union { i32, f32 }`,
		`package fixture
@(tag="cabi") U :: struct #raw_union { a: i32, b: f32 }`,
		`package fixture
@(tag="cabi_opaque") U :: union { i32, f32 }`,
		`package fixture
Missing :: struct { x: i32 }
@(tag="cabi") bad :: proc(value: Missing) {}`,
		`package fixture
@(tag="cabi_opaque") Hidden :: struct { x: i32 }
@(tag="cabi") bad :: proc(value: []Hidden) {}`,
		`package fixture
when true { @(tag="cabi") bad :: proc() {} }`,
		`package fixture
f :: proc() {}
@(tag="cabi") bad :: proc{f}`,
		`package fixture
@(tag="cabi") bad :: proc(f: proc()) {}`,
		`package fixture
@(tag="cabi") bad :: proc(value: $T) {}`,
	}
	for source in sources {
		m := parse_test_model(t, source)
		testing.expect(t, m.errors > 0, source)
	}
}

@test
unselected_types_and_opaque_fields_are_ignored :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	m := parse_test_model(t, `package fixture
Unrelated :: union { i32, f32 }
@(tag="cabi_opaque") Hidden :: struct { data: Unrelated }
@(tag="cabi") free_hidden :: proc(value: ^Hidden) {}
`)
	testing.expect_value(t, m.errors, 0)
	header := emit_header(&m)
	testing.expect(t, !strings.contains(header, "Unrelated"))
	testing.expect(t, !strings.contains(header, "struct Fixture_Hidden {"))
}

@test
generated_files_are_removed_before_parsing :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	pkg := ast.new(ast.Package, tokenizer.Pos{}, tokenizer.Pos{})
	generated := ast.new(ast.File, tokenizer.Pos{}, tokenizer.Pos{})
	generated.src = fmt.tprintf("%s\nthis is deliberately invalid Odin", MARKER)
	pkg.files["cgen.odin"] = generated
	source := ast.new(ast.File, tokenizer.Pos{}, tokenizer.Pos{})
	source.src = "package fixture\n"
	source.fullpath = "fixture.odin"
	pkg.files[source.fullpath] = source
	exclude_generated(pkg)
	testing.expect_value(t, len(pkg.files), 1)
	testing.expect(t, parser.parse_package(pkg))
}
