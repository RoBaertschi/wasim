package wasim_base

import "core:fmt"
import "core:time"
import "core:container/intrusive/list"
import "base:runtime"
import "core:mem/virtual"

Perf_Node :: struct {
	node:     list.Node,
	location: runtime.Source_Code_Location,
	start:    time.Tick,
}

Perf_State :: struct {
	arena: virtual.Arena,
	free:  ^Perf_Node,
	stack: list.List,
}

@(thread_local)
perf_state: Perf_State

PERF_ENABLED :: #config(PERF, false)

_perf_pop_deferred :: proc(procedure: runtime.Source_Code_Location) {
	node := perf_pop()
	_ = assert(node.location == procedure)
	diff := time.tick_diff(node.start, time.tick_now())
	fmt.printfln("%v:%v took %v", procedure.file_path, procedure.procedure, diff)
}

@(disabled=!PERF_ENABLED, deferred_in=_perf_pop_deferred)
perf_scoped :: proc(procedure := #caller_location) {
	perf_push(procedure)
}

perf_push :: proc(procedure := #caller_location) {
	node: ^Perf_Node
	if perf_state.free != nil {
		node            = perf_state.free
		perf_state.free = container_of(node.node.next, Perf_Node, "node")
	} else {
		node = arena_new(&perf_state.arena, Perf_Node)
	}

	node.start    = time.tick_now()
	node.location = procedure
	list.push_back(&perf_state.stack, &node.node)
}

perf_pop :: proc() -> ^Perf_Node {
	node_node := list.pop_back(&perf_state.stack)
	node      := container_of(node_node, Perf_Node, "node")

	node_node.next  = &perf_state.free.node if perf_state.free != nil else nil
	perf_state.free = node
	return node
}
