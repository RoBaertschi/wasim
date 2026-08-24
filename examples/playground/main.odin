package wasim_examples_playground

import "core:fmt"

main :: proc() {
	fmt.printfln("min(%x), max(%x)", transmute(u32)min(i32), transmute(u32)max(i32))
}
