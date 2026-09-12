package wasim_base

import "base:intrinsics"
import "base:builtin"

when ODIN_DISABLE_ASSERT {
	@require_results
	assert :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) -> bool {
		return intrinsics.expect(condition, true)
	}
} else {
	@require_results
	assert :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) -> bool {
		builtin.assert(condition, message, loc)
		return condition
	}
}

assert_always :: proc(condition: bool, message := #caller_expression(condition), loc := #caller_location) {
	builtin.ensure(condition, message, loc)
}
