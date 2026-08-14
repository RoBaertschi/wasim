package wasim_base

import "core:fmt"
import "base:sanitizer"
import "core:mem/virtual"
import "core:mem"
import "base:runtime"

Arena_Flag :: enum {
	No_Growing,
}

Arena_Flags :: bit_set[Arena_Flag]

Arena :: struct {
	prev:             ^Arena,
	curr:             ^Arena,
	flags:            Arena_Flags,
	base_pos:         uint, // absolute pos in linked list chain
	data:             uintptr,
	used:             uint,
	reserved:         uint,
	commited:         uint,
	initial_commited: uint,
}

@(private="file")
oom :: proc(err := mem.Allocator_Error.Out_Of_Memory) -> ! {
	fmt.panicf("Out of memory: %v", err)
}

arena_alloc :: proc(commited: uint = 0, reserved: uint = runtime.Gigabyte * 2, flags: Arena_Flags = {}) -> ^Arena {
	a := Arena {
		used             = 0,
		reserved         = reserved,
		commited         = commited,
		initial_commited = commited,
	}

	data, err := virtual.reserve(reserved)
	if err != nil {
		// TODO(robin): better error message
		oom(err)
	}

	err = virtual.commit(raw_data(data), commited)
	if err != nil {
		// TODO(robin): better error message
		oom(err)
	}

	sanitizer.address_poison(data)

	a.data = uintptr(raw_data(data))
	a.curr = &a

	arena      := arena_push_clone(&a, a)
	arena.curr  = arena

	return arena
}

arena_destroy_single :: proc(a: ^Arena) {
	virtual.release(rawptr(a.data), a.reserved)
}

arena_destroy :: proc(a: ^Arena) {
	prev := a.curr.prev
	for curr := a.curr; curr != nil; curr = prev {
		prev = curr.prev

		arena_destroy_single(curr)
	}
}

_arena_push_aligned_non_zeroed :: proc(a: ^Arena, size: uint, align: uint) -> (data: []byte) {
	if size == 0 {
		return nil
	}

	curr := a.curr

	arena_align_used :: proc(a: ^Arena, align: uint) -> uint {
		return uint(mem.align_forward_uintptr(uintptr(a.used) + a.data, uintptr(align)) - a.data)
	}

	curr_used_aligned := arena_align_used(curr, align)
	if curr_used_aligned + size > curr.reserved {
		if .No_Growing in a.flags {
			oom()
		}

		reserved := mem.align_forward_uint(max(curr.reserved,         size + size_of(Arena)), uint(mem.PAGE_SIZE))
		commited := mem.align_forward_uint(max(curr.initial_commited, size + size_of(Arena)), uint(mem.PAGE_SIZE))

		new_arena := arena_alloc(
			commited,
			reserved,
			a.flags,
		)

		new_arena.base_pos = curr.base_pos + curr.used
		new_arena.prev     = curr

		a.curr = new_arena
		curr   = new_arena

		curr_used_aligned = arena_align_used(curr, align)
	}

	start := curr_used_aligned
	end   := start + size

	start_padding := curr.used
	end_padding   := curr_used_aligned

	if !assert(end <= curr.reserved) {
		end = curr.reserved
	}

	if curr.commited < end {
		next_commit_boundary := mem.align_forward_uint(end, uint(mem.PAGE_SIZE))
		if assert(next_commit_boundary > curr.commited) {
			_ = assert(next_commit_boundary <= curr.reserved)

			err := virtual.commit(rawptr(curr.data + uintptr(curr.commited)), next_commit_boundary - curr.commited)
			if err != nil {
				oom(err)
			}

			curr.commited = next_commit_boundary
		}
	}

	curr.used = end
	data      = ([^]byte)(curr.data)[start:end]
	padding  := ([^]byte)(curr.data)[start_padding:end_padding]

	sanitizer.address_unpoison(padding)
	sanitizer.address_unpoison(data)

	return
}

_arena_push_aligned :: proc(a: ^Arena, size: uint, align: uint) -> (data: []byte) {
	data = _arena_push_aligned_non_zeroed(a, size, align)
	mem.zero_slice(data)
	return
}

arena_pop_to :: proc(a: ^Arena, pos: uint, loc := #caller_location) {
	pos := pos

	// don't allow to deallocate the initial arena
	pos = max(pos, size_of(Arena))

	curr := a.curr

	curr_pos := curr.base_pos + curr.used

	if !assert(pos <= curr_pos, loc = loc) {
		return
	}

	for prev := curr.prev; pos <= curr.base_pos; curr = prev {
		prev = curr.prev

		a.curr = prev
		arena_destroy_single(curr)
	}

	a.curr = curr

	new_used := pos - curr.base_pos

	sanitizer.address_poison(rawptr(curr.data + uintptr(new_used)), curr.used - new_used)

	curr.used = new_used
}

arena_pop :: proc(a: ^Arena, size: int, loc := #caller_location) {
	size := size

	curr := a.curr
	used := curr.base_pos + curr.used

	if !assert(0 <= size) {
		return
	}

	size_uint := uint(size)

	if !assert(size_uint <= used) {
		size_uint = used
	}

	arena_pop_to(a, used - size_uint, loc = loc)
}

arena_clear :: proc(a: ^Arena) {
	arena_pop_to(a, 0)
}

Arena_Temp :: struct {
	arena: ^Arena, 
	pos:   uint,
}

arena_temp_begin :: proc(a: ^Arena) -> Arena_Temp {
	return {
		arena = a,
		pos   = a.curr.base_pos + a.curr.used,
	}
}

arena_temp_end :: proc(temp: Arena_Temp, loc := #caller_location) {
	arena_pop_to(temp.arena, temp.pos, loc = loc)
}

@(deferred_out=arena_temp_end)
arena_guard :: proc(a: ^Arena, loc := #caller_location) -> (temp: Arena_Temp, out_loc: runtime.Source_Code_Location) {
	temp    = arena_temp_begin(a)
	out_loc = loc
	return
}

// Allocator compat

// TODO(robin): we could store the last alignment padding to waste a little less space, but that does not seem worth it for now
arena_allocator_proc : mem.Allocator_Proc : proc(
	allocator_data: rawptr, mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr, old_size: int,
	location: runtime.Source_Code_Location = #caller_location,
) -> (data: []byte, err: mem.Allocator_Error) {
	a := cast(^Arena)allocator_data

	switch mode {
	case .Alloc:
		data = _arena_push_aligned(a, uint(size), uint(alignment))
	case .Alloc_Non_Zeroed:
		data = _arena_push_aligned_non_zeroed(a, uint(size), uint(alignment))
	case .Resize:
		is_last_allocation := a.curr.data + uintptr(a.curr.used) - uintptr(old_size) == uintptr(old_memory)

		if old_memory == nil {
			data = _arena_push_aligned(a, uint(size), uint(alignment))
		} else if size == 0 && !is_last_allocation {
			err = .Mode_Not_Implemented
		} else {
			if is_last_allocation {
				// this is the last allocation, resize
				a.curr.used = a.curr.used - uint(old_size) // pop of old allocation
				data = _arena_push_aligned_non_zeroed(a, uint(size), uint(alignment))

				if old_size < size {
					mem.zero_slice(data[old_size:])
				}
			} else {
				// not last allocation, just allocate more
				data = _arena_push_aligned(a, uint(size), uint(alignment))
			}
			old_data := ([^]byte)(old_memory)[:old_size]
			
			// In case we want to keep the padding poisoned
			// @(no_sanitize_address)
			// move_forward_no_sanitize :: proc(dst, src: []byte) {
			// 	n := min(len(dst), len(src))
			//
			// 	// If this is not true, we would start corrupting data and thats not acceptable
			// 	assert_always(uintptr(raw_data(dst)) >= uintptr(raw_data(src)))
			//
			// 	if n > 0 {
			// 		#no_bounds_check for i in 1..=n {
			// 			dst[n-i] = src[n-i]
			// 		}
			//
			// 		// NOTE: mem_copy would be the better choice, but address sanitation always applies for those
			// 		// intrinsics.mem_copy(raw_data(dst), raw_data(src), n)
			// 	}
			// }
			//
			// if raw_data(data) != raw_data(old_data) {
			// 	move_forward_no_sanitize(data, old_data)
			// }

			copy(data, old_data)
		}
	case .Free_All:
		arena_clear(a)
	case .Resize_Non_Zeroed, .Free, .Query_Info:
		err = .Mode_Not_Implemented
	case .Query_Features:
		set := cast(^runtime.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = { .Alloc, .Alloc_Non_Zeroed, .Free_All, .Resize, .Query_Features }
		}
	}

	return
}

arena_allocator :: proc(a: ^Arena) -> mem.Allocator {
	return {
		data      = a,
		procedure = arena_allocator_proc,
	}
}

// Tests

import "core:testing"

@test
arena_lifecycle_test :: proc(t: ^testing.T) {
	arena := arena_alloc()
	defer arena_destroy(arena)

	i  := arena_push(arena, 3)
	testing.expect_value(t, i^, 3)
	i^  = 2
	testing.expect_value(t, i^, 2)
}

@test
arena_allocate_across_reserve_test :: proc(t: ^testing.T) {
	arena := arena_alloc(0, uint(mem.PAGE_SIZE))
	defer arena_destroy(arena)

	lots_of_data := arena_push_make(arena, []byte, 100000)
	_ = lots_of_data

	arena_pop(arena, 100000 + size_of(Arena))
	testing.expect_value(t, arena.curr, arena)
}

@test
arena_clear_test :: proc(t: ^testing.T) {
	arena := arena_alloc(0, uint(mem.PAGE_SIZE))
	defer arena_destroy(arena)

	lots_of_data := arena_push_make(arena, []byte, 100000)
	_ = lots_of_data

	arena_clear(arena)
	testing.expect_value(t, arena.curr, arena)
	testing.expect_value(t, arena.used, size_of(Arena))
}

@test
arena_guard_test :: proc(t: ^testing.T) {
	arena := arena_alloc()
	defer arena_destroy(arena)

	{
		arena_guard(arena)

		i := arena_push(arena, int)
		i^ = 202020
	}

	testing.expect_value(t, arena.used, size_of(Arena))
}

@test
arena_allocator_test :: proc(t: ^testing.T) {
	arena := arena_alloc()
	defer arena_destroy(arena)

	context.allocator = arena_allocator(arena)

	i := new(int)
	i^ = 2
	testing.expect_value(t, free(i), mem.Allocator_Error.Mode_Not_Implemented)
	i^ = 4
	free_all()

	testing.expect_value(t, arena.used, size_of(Arena))

	pad  := new(u8)
	_     = pad
	data := new(u16)
	data^ = 0x4422
	testing.expect(t, mem.is_aligned(data, align_of(u16)))
	new_data, _ := mem.resize(data, size_of(u16), size_of(u16))
	testing.expect_value(t, (^u16)(new_data)^, 0x4422)
	testing.expect(t, mem.is_aligned(new_data, mem.DEFAULT_ALIGNMENT))
	testing.expect(t, new_data != data)
	freed_data, _ := mem.resize(new_data, size_of(u16), 0)
	_ = freed_data
}

@test
arena_allocator_same_address_resize_test :: proc(t: ^testing.T) {
	arena := arena_alloc(0, uint(mem.PAGE_SIZE))
	defer arena_destroy(arena)
	allocator := arena_allocator(arena)

	old, err := mem.alloc(16, 8, allocator)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	old_bytes := ([^]u8)(old)[:16]
	for &b, i in old_bytes {
		b = u8(i + 1)
	}

	resized: rawptr
	resized, err = mem.resize(old, 16, 32, 8, allocator)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, resized, old)

	bytes := ([^]u8)(resized)[:32]
	for i in 0..<16 {
		testing.expect_value(t, bytes[i], u8(i + 1))
	}
	for i in 16..<32 {
		testing.expect_value(t, bytes[i], u8(0))
	}
}

@test
arena_allocator_overflow_resize_test :: proc(t: ^testing.T) {
	arena := arena_alloc(0, uint(mem.PAGE_SIZE))
	defer arena_destroy(arena)
	allocator := arena_allocator(arena)

	old, err := mem.alloc(100_000, 8, allocator)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	old_bytes := ([^]u8)(old)[:100_000]
	for i in 0..<64 {
		old_bytes[i] = u8(i + 1)
	}

	root_used := arena.used
	old_curr := arena.curr
	testing.expect(t, old_curr != arena)

	resized: rawptr
	resized, err = mem.resize(old, 100_000, 120_000, 8, allocator)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, arena.used, root_used)
	testing.expect(t, arena.curr != old_curr)

	bytes := ([^]u8)(resized)[:120_000]
	for i in 0..<64 {
		testing.expect_value(t, bytes[i], u8(i + 1))
	}
	for i in 100_000..<120_000 {
		testing.expect_value(t, bytes[i], u8(0))
	}
}

// NOTE: for testing only
//
// @(test, disabled=.Address in ODIN_SANITIZER_FLAGS)
// arena_address_sanitation_test :: proc(t: ^testing.T) {
// 	testing.expect_signal(t, libc.SIGABRT)
// 	arena := arena_alloc()
// 	defer arena_destroy(arena)
//
// 	i: ^int
// 	{
// 		arena_guard(arena)
//
// 		i = new(arena, int)
// 		i^ = 202020
// 	}
//
// 	i^ = 3
// }
