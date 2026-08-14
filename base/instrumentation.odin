package wasim_base

import "core:time"
import "base:intrinsics"
import "base:runtime"

import "core:fmt"
import "core:mem/virtual"
import "core:hash/xxhash"

INST_DISABLE :: #config(INST_DISABLE, false)

Inst_Key :: distinct u128

INST_KEY_ZERO :: Inst_Key(0)

inst_key_from_loc :: proc(loc: runtime.Source_Code_Location) -> (key: Inst_Key) {
	loc := loc

	state: xxhash.XXH3_state
	xxhash.XXH3_128_reset(&state)
	xxhash.XXH3_128_update(&state, transmute([]byte)loc.file_path)
	xxhash.XXH3_128_update(&state, bytes_from_ptr(&loc.line))
	xxhash.XXH3_128_update(&state, bytes_from_ptr(&loc.column))
	xxhash.XXH3_128_update(&state, transmute([]byte)loc.procedure)

	key = Inst_Key(xxhash.XXH3_128_digest(&state))

	if key == 0 {
		key = 1
	}
	return
}

Inst_Node :: struct {
	// metadata
	key:       Inst_Key,
	hash_next: ^Inst_Node, // hash map bucket list
	next:      ^Inst_Node, // iteration list

	// data
	name:                 string,
	self_cycles:          u64,
	total_cycles:         u64,
	hits:                 int,
	processed_byte_count: int,
}

Inst_Deferred :: struct {
	node:             ^Inst_Node,
	name:             string,
	start:            u64,
	parent:           ^Inst_Node,
	old_total_cycles: u64,
}

Inst_State :: struct {
	arena:   virtual.Arena,
	freq:    u64,
	start:   u64,
	first:   ^Inst_Node,
	last:    ^Inst_Node,
	current: ^Inst_Node,

	inst_map: []^Inst_Node,
}

inst_state: ^Inst_State

inst_node_from_key :: proc(key: Inst_Key) -> (node: ^Inst_Node) {
	idx   := u128(key) % u128(len(inst_state.inst_map))
	entry := &inst_state.inst_map[idx]

	for {
		if entry^ == nil {
			node, _  = virtual.new(&inst_state.arena, Inst_Node)
			node.key = key

			if intrinsics.likely(inst_state.last != nil) {
				inst_state.last.next = node
			} else {
				inst_state.first = node
			}
			inst_state.last = node

			entry^ = node
			break
		}

		if entry^.key == key {
			node = entry^
			break
		}

		entry = &entry^.hash_next
	}

	return
}

inst_begin_profile :: proc() {
	inst_state, _ = virtual.arena_growing_bootstrap_new(Inst_State, "arena")

	inst_state.freq        = get_cpu_freq(100 * time.Millisecond)
	inst_state.inst_map, _ = virtual.make(&inst_state.arena, []^Inst_Node, 4096)

	node      := inst_node_from_key(INST_KEY_ZERO)
	node.name = "Total"

	inst_state.current = node
	inst_state.start   = read_cpu_timer()
}

inst_end_profile :: proc() {
	_ = assert(inst_state.current == inst_state.first)

	cur             := inst_state.first
	dur             := read_cpu_timer() - inst_state.start
	cur.self_cycles  = dur

	fmt.println("\n=== Profiling Results ===\n")

	fmt.printfln("Total time: %v (CPU freq %v)", cpu_time_duration(dur, inst_state.freq), inst_state.freq)
	for node := inst_state.first.next; node != nil; node = node.next {
		node_self_cycles := node.self_cycles

		node_self_percent  := f64(node_self_cycles) / f64(dur)
		node_self_percent  *= 100

		node_total_percent := f64(node.total_cycles) / f64(dur)
		node_total_percent *= 100

		fmt.printf("  %s[%v]: %v(%v, %.3f%%", node.name, node.hits, node_self_cycles, cpu_time_duration(node_self_cycles, inst_state.freq), node_self_percent)
		if node.total_cycles != node_self_cycles {
			fmt.printf(", w/ children=%.3f%%", node_total_percent)
		}
		fmt.print(")")

		if node.processed_byte_count != 0 {
			seconds   := f64(node.total_cycles) / f64(inst_state.freq)
			megabytes := f64(node.processed_byte_count) / runtime.Megabyte
			bandwidth := gigabytes_per_second(node.processed_byte_count, seconds)

			fmt.printf(" %.3fmb at %.2fgb/s", megabytes, bandwidth)
		}

		fmt.println()
	}
}

when !INST_DISABLE {
	inst_begin :: proc(name: string, bytes := 0, loc := #caller_location) -> (deferred: Inst_Deferred) {
		deferred.node             = inst_node_from_key(inst_key_from_loc(loc))
		deferred.name             = name
		deferred.start            = read_cpu_timer()
		deferred.parent           = inst_state.current
		deferred.old_total_cycles = deferred.node.total_cycles

		deferred.node.processed_byte_count += bytes

		inst_state.current = deferred.node
		return
	}

	inst_end :: proc(deferred: Inst_Deferred) {
		elapsed_cycles := read_cpu_timer() - deferred.start

		_ = assert(inst_state.current == deferred.node)

		node      := deferred.node
		node.hits += 1
		node.name  = deferred.name

		deferred.parent.self_cycles -= elapsed_cycles
		node.self_cycles            += elapsed_cycles
		node.total_cycles            = deferred.old_total_cycles + elapsed_cycles

		inst_state.current = deferred.parent
	}

	@(deferred_out=inst_end)
	inst_proc :: proc(bytes := 0, loc := #caller_location) -> Inst_Deferred {
		return inst_begin(loc.procedure, bytes = bytes, loc = loc)
	}

	@(deferred_out=inst_end)
	inst_scope :: proc(name: string, bytes := 0, loc := #caller_location) -> Inst_Deferred {
		return inst_begin(name, bytes = bytes, loc = loc)
	}

} else {
	inst_begin :: #force_inline proc(name: string, bytes := 0, loc := #caller_location) -> (deferred: Inst_Deferred) { return }

	inst_end :: #force_inline proc(deferred: Inst_Deferred) {}

	inst_proc :: #force_inline proc(bytes := 0, loc := #caller_location) -> (deferred: Inst_Deferred) { return }

	inst_scope :: #force_inline proc(name: string, bytes := 0, loc := #caller_location) -> (deferred: Inst_Deferred) { return }
}
