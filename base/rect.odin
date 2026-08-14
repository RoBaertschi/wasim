package wasim_base

import "base:intrinsics"

import "core:math"

Rect :: struct($T: typeid) where intrinsics.type_is_comparable(T) {
	pos:  [2]T,
	size: [2]T,
}

rect_cast :: proc(rect: Rect($FROM), $TO: typeid) -> Rect(TO) {
	return {
		pos  = { TO(rect.pos.x),  TO(rect.pos.y) },
		size = { TO(rect.size.x), TO(rect.size.y) },
	}
}

rect_contains :: proc(rect: Rect($T), pos: [2]T) -> bool {
	return (rect.pos.x <= pos.x && pos.x < (rect.pos.x + rect.size.x)) && (rect.pos.y <= pos.y && pos.y < (rect.pos.y + rect.size.y))
}

rect_intersection :: proc(a, b: Rect($T)) -> (rect: Rect(T)) {
	a_right  := a.pos.x + a.size.x
	a_bottom := a.pos.y + a.size.y
	b_right  := b.pos.x + b.size.x
	b_bottom := b.pos.y + b.size.y
	rect = {
		pos = {
			max(a.pos.x, b.pos.x),
			max(a.pos.y, b.pos.y),
		},
	}

	rect.size = {
		min(a_right, b_right) - rect.pos.x,
		min(a_bottom, b_bottom) - rect.pos.y,
	}

	return
}

rect_padding :: proc(rect: Rect($T), padding: T) -> Rect(T) {
	return {
		pos  = rect.pos  - padding,
		size = rect.size + padding,
	}
}

rect_clamp_x_pos :: proc(rect: Rect($T), pos: T) -> T {
	return clamp(pos, rect.pos.x, rect.pos.x + rect.size.x)
}

rect_f32_to_int :: proc(rect: Rect(f32)) -> Rect(int) {
	return {
		pos = {
			int(math.floor(rect.pos.x)),
			int(math.floor(rect.pos.y)),
		},
		size = {
			int(math.ceil(rect.size.x)),
			int(math.ceil(rect.size.y)),
		},
	}
}
