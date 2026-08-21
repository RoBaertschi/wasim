package wasim_example_decoder

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
		B.bin_read(data, os.name(cmd.input_module), []^B.Arena{ B.arena_alloc(), B.arena_alloc(), B.arena_alloc() })
	} else {
		fmt.eprintfln("could not read file %s: %v", os.name(cmd.input_module), err)
	}
}
