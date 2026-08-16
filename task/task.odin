package wasim_task

import "core:strings"
import "core:path/filepath"
import "core:fmt"
import "core:os"
import "core:flags"

main :: proc() {
	Cmd :: struct {
		task: string `args:"pos=0,required"`,
		overflow: [dynamic]string,
	}

	cmd: Cmd
	flags.parse_or_exit(&cmd, os.args)

	switch cmd.task {
	case "run":
		if len(cmd.overflow) < 1 {
			fmt.eprintln("missing test file for run")
			flags.write_usage(os.to_stream(os.stderr), Cmd, os.args[0]); os.exit(1)
		}

		file := strings.concatenate({ cmd.overflow[0], ".wasm" }, allocator = context.temp_allocator)
		file_path, _ := filepath.join({"./test_files", file}, allocator = context.temp_allocator)

		desc := os.Process_Desc{
			command = { "odin", "run", ".", "-vet", "--", file_path },
			stdout  = os.stdout,
			stderr  = os.stderr,
			stdin   = os.stdin,
		}

		p, err := os.process_start(desc)
		if err != nil {
			fmt.eprintfln("could not spawn process: %v", err)
			os.exit(1)
		}

		state: os.Process_State
		state, err = os.process_wait(p)

	case: flags.write_usage(os.to_stream(os.stderr), Cmd, os.args[0]); os.exit(1)
	}
}
