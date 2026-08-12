package wasim

import "core:math/bits"
import "base:intrinsics"
import "core:mem/virtual"
import "core:flags"
import "core:os"
import "core:fmt"
import "core:encoding/varint"

MAGIC   :: u32(0x6D736100)
VERSION :: u32(1)

Binary_Reader :: struct {
	data: []byte,
	pos:  int,
	file: string,
	m:    ^Module,

	errors: int,
}

Section_Kind :: enum byte {
	Custom,
	Type,
	Import,
	Function,
	Table,
	Memory,
	Global,
	Export,
	Start,
	Element,
	Code,
	Data,
}

Section :: struct {
	kind: Section_Kind,
	size: int,
}

Section_Node :: struct {
	next:    ^Section_Node,
	section: Section,
}

Section_List :: List(Section_Node)

Module :: struct {
	arena:    virtual.Arena,
	version:  int,
	sections: Section_List,
}

errorf :: proc(r: ^Binary_Reader, pos: int, format: string, args: ..any) {
	r.errors += 1

	fmt.printf("%v:%v: WASM Binary Error: ", r.file, pos)
	fmt.printfln(format, ..args)
}

reader_data_left :: proc(r: ^Binary_Reader) -> int {
	return len(r.data) - r.pos
}

read_bytes :: proc(r: ^Binary_Reader, count: int) -> (bytes: []byte, ok: bool) {
	if count <= reader_data_left(r) {
		bytes = r.data[r.pos:r.pos+count]
		ok    = true

		r.pos += count
	} else {
		errorf(r, r.pos, "missing bytes")
	}

	return
}

read_t :: proc(r: ^Binary_Reader, $T: typeid) -> (value: T, ok: bool) {
	data: []byte
	data, ok = read_bytes(r, size_of(T))

	if ok {
		value = (^T)(raw_data(data))^
	}

	return
}

read_uXX_leb :: proc(r: ^Binary_Reader, $T: typeid) -> (value: T, ok: bool) where intrinsics.type_is_integer(T), intrinsics.type_is_unsigned(T) {
	MAX_BYTES :: int(intrinsics.constant_ceil(f64(size_of(value) * 8) / 7))
	MAX       :: u128(max(T))

	value_u128, size, err := varint.decode_uleb128_buffer(r.data[r.pos:])
	switch err {
	case .None:
		// validate LEB u32 size
		if size <= MAX_BYTES {
			if value_u128 <= MAX {
				// valid LEB u32 found
				ok     = true
				value  = T(value_u128)
				r.pos += size
			} else {
				errorf(r, r.pos, "LEB %[0]v has value to large to fit into a %[0]v: %v <= %v", typeid_of(T), value_u128, MAX)
			}
		} else {
			errorf(r, r.pos, "LEB has to many bytes for a %v: %v <= %v", typeid_of(T), size, MAX_BYTES)
		}
	case .Buffer_Too_Small: errorf(r, r.pos, "missing bytes for LEB %v", typeid_of(T))
	case .Value_Too_Large:  errorf(r, r.pos, "LEB to large to even fit into a u128")
	}

	return
}

read_u32 :: proc(r: ^Binary_Reader) -> (u32, bool) { return read_t(r, u32) }

read_u32_leb :: proc(r: ^Binary_Reader) -> (value: u32, ok: bool) { return read_uXX_leb(r, u32) }

as :: proc($T: typeid, a: $A, ok: bool) -> (T, bool) {
	return (T)(a), ok
}

read_section :: proc(r: ^Binary_Reader) -> (section: Section, ok: bool) {
	section.kind, ok = read_t(r, Section_Kind)
	if ok {
		section.size, ok = as(int, read_u32_leb(r))
		if ok {
			r.pos += section.size
		}
	}

	return
}

read_sections_into_module :: proc(r: ^Binary_Reader) -> (ok: bool) {
	ok = true

	for r.pos < len(r.data) {
		section: Section
		section, ok = read_section(r)
		if ok {
			node, _ := virtual.new(&r.m.arena, Section_Node)
			node.section = section
			list_push(&r.m.sections, node)
		} else {
			break
		}
	}

	return
}

read_module :: proc(r: ^Binary_Reader) -> (ok: bool) {
	r.m, _ = virtual.arena_growing_bootstrap_new(Module, "arena")

	// read magic number
	magic: u32
	magic, ok = read_u32(r)
	if ok {
		if magic == MAGIC {

			// read version number
			version: u32
			version, ok = read_u32(r)
			if ok {
				if version == VERSION {
					// read sections
					ok = read_sections_into_module(r)

					if ok {
						fmt.printfln("found module with version %v", version)
						for section_node := r.m.sections.first; section_node != nil; section_node = section_node.next {
							section := section_node.section
							fmt.printfln("found section of type %v", section)
						}
					}
				} else {
					errorf(r, r.pos-size_of(version), "unsupported WASM version %v, currently only WASM 1.0 is supported", version)
				}
			}
		} else {
			errorf(r, r.pos-size_of(magic), "invalid magic number %v, expected %v", magic, MAGIC)
		}
	}

	return
}

main :: proc() {
	Cmd :: struct {
		input_module: ^os.File `args:"pos=0,required"`,
	}

	cmd: Cmd

	flags.parse_or_exit(&cmd, os.args, allocator = context.temp_allocator)

	data, err := os.read_entire_file(cmd.input_module, context.temp_allocator)
	if err == nil {
		r := Binary_Reader {
			data = data,
			file = os.name(cmd.input_module),
		}

		read_module(&r)
	} else {
		fmt.eprintfln("could not read file %q: %v", os.name(cmd.input_module), err)
	}
}
