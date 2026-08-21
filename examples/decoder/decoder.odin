package wasim_example_decoder

import "core:flags"
import "core:fmt"
import "core:os"
import "../.."
import B "../../base"

main :: proc() {
	Cmd :: struct {
		input_module: ^os.File `args:"pos=0,required"`,
		thread_count: int,
	}

	cmd: Cmd

	flags.parse_or_exit(&cmd, os.args, allocator = context.temp_allocator)

	data, err := os.read_entire_file(cmd.input_module, context.temp_allocator)
	if err == nil {
		// spawn 3 threads

		cmd.thread_count = max(cmd.thread_count, 1)

		temp := B.TEMP_ALLOCATOR_GUARD()
		thread_arenas := B.arena_push_make(temp, []^B.Arena, cmd.thread_count)

		for &thread_arena in thread_arenas {
			thread_arena = B.arena_alloc()
		}

		module, diagnostics := wasim.bin_read(data, os.name(cmd.input_module), thread_arenas)
		_ = module

		if 0 < len(diagnostics) {
			fmt.eprintfln("malformed module, found %v errors:", len(diagnostics))
			for diag in diagnostics {
				fmt.eprintfln("%v:%v-%v:Error: %v", os.name(cmd.input_module), diag.range.start, diag.range.end, diag.error)
			}
		} else {
			fmt.printfln("found module with version %v", module.version)
			fmt.printfln("%#v", module)
		}
	} else {
		fmt.eprintfln("could not read file %s: %v", os.name(cmd.input_module), err)
	}
}
