package wasim

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

read_u32 :: proc(r: ^Binary_Reader) -> (u32, bool) { return read_t(r, u32) }

read_section :: proc() -> (section: Section, ok: bool) {}

read_module :: proc(r: ^Binary_Reader) -> (ok: bool) {
	magic: u32
	magic, ok = read_u32(r)

	if ok {
		if magic == MAGIC {
			version: u32
			version, ok = read_u32(r)
			if ok {
				if version == VERSION {
					fmt.printfln("found module with version %v", version)
					ok = true
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
