package wasim

import "core:fmt"
import "core:encoding/varint"
main :: proc() {
	fmt.println(varint.decode_ileb128([]u8{ 0x40 }))
}
