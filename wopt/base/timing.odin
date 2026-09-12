package wasim_base

import "base:intrinsics"
import "base:runtime"

import "core:time"

get_cpu_freq :: proc(fallback_sleep := 2 * time.Second) -> (result: u64) {
	result, _ = time.tsc_frequency(fallback_sleep)
	return
}

read_cpu_timer :: proc() -> (result: u64) {
	result = u64(intrinsics.read_cycle_counter())
	return
}

gigabytes_per_second :: proc(byte_count: int, seconds: f64) -> f64 {
	return f64(byte_count) / seconds / runtime.Gigabyte
}

cycles_per_nanosecond :: proc(freq: u64) -> (result: u64) {
	result = freq / 1000 / 1000 / 1000
	return
}

cpu_time_start_end :: proc(start, end, freq: u64) -> (result: time.Duration) {
	duration := u128(end - start) * 1_000_000_000

	result = time.Duration(duration / u128(freq))
	return
}

cpu_time_duration :: proc(duration_cycles, freq: u64) -> (result: time.Duration) {
	duration := u128(duration_cycles) * 1_000_000_000

	result = time.Duration(duration / u128(freq))
	return
}
