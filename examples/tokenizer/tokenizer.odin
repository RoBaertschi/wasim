package wasim_example_tokenizer

import "core:flags"
import "core:fmt"
import "core:os"
import wasim "../.."

main :: proc() {
	Cmd :: struct {
		input_file: ^os.File `args:"pos=0,required"`,
	}

	cmd: Cmd
	flags.parse_or_exit(&cmd, os.args, allocator = context.temp_allocator)

	data, err := os.read_entire_file(cmd.input_file, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("could not read file %s: %v", os.name(cmd.input_file), err)
		return
	}

	tokenizer: wasim.Tex_Tokenizer
	wasim.tex_tok_init(&tokenizer, string(data), os.name(cmd.input_file))

	for {
		token := wasim.tex_tok_next(&tokenizer)
		fmt.printfln("%v %q", token.kind, token.data)

		if token.kind == .Eof {
			break
		}
	}
}
