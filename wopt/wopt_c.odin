package wopt

import "base:runtime"

@export
wopt_module_new :: proc "c" () -> ^Module {
	context = runtime.default_context()
	return module_new()
}

@export
wopt_module_free :: proc "c" (m: ^Module) {
	context = runtime.default_context()
	module_free(m)
}
