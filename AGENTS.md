# Repository Guide

## Commands

- Type-check the library and runnable packages separately: `odin test . -all-packages`, `odin check examples/decoder -vet -warnings-as-errors`, and `odin check task -vet -warnings-as-errors`. Plain `odin check .` fails because the root package is a library with no `main`.
- Run the complete test suite, including imported packages: `odin test . -all-packages`.
- Run only the `base` package tests: `odin test base`.
- Run one test: `odin test base -- -tests:arena_lifecycle_test`. Test filtering is a test-runner argument after `--`, not an Odin compiler flag.
- Build outside the worktree with `odin build examples/decoder -out:/tmp/wasim-decoder`, then smoke-test with `/tmp/wasim-decoder test_files/empty.wasm -thread-count:2`. Application options use Odin's colon syntax; `-thread-count 2` is parsed incorrectly.
- `task/task.odin` still runs `odin run .`, so `odin run task -- run empty` currently reports the root package's missing `main`; do not use it as the parser runner without fixing it first.
- There is no repo-local task runner, formatter configuration, CI workflow, or code-generation command. The checked-in `.wasm` fixtures have no documented regeneration flow.

## Package Layout

- The root `.odin` files form library package `wasim`; `bin_read` and the parallel WASM reader are in `wasim_binary.odin`. The CLI entrypoint is `examples/decoder/decoder.odin`.
- `base/` is a separate imported package named `wasim_base`, aliased as `B` by the executable. Its `@test` procedures are embedded in implementation files rather than `*_test.odin` files.
- `base/arena.odin` implements the project's custom virtual-memory arena; do not confuse it with `core:mem/virtual.Arena`, which is also used by some base utilities.

## Parallel Reader

- Every reader thread must receive a `B.Lane_Ctx` and call `B.lane_select_ctx` before using lane helpers. The shared `sync.Barrier` participant count must exactly match the lane count.
- Lane 0 scans the module header and section table, then `B.lane_sync_value` broadcasts shared values. Non-code sections and function bodies are distributed with lane ranges.
- `B.lane_sync_value` only supports values no larger than `u128` and deliberately performs two barrier waits around the shared scratch word.
- The shared `sync.One_Shot_Event` means lane 0 has completed `bin_read_entry_point`; it does not count worker completion. `bin_read` still joins every created thread afterward.

## Project-Specific Behavior

- `B.TEMP_ALLOCATOR_GUARD` uses per-thread arenas and rolls allocations back at scope exit. Preserve pointed-to data in a longer-lived arena before leaving that scope.
- Instrumented scopes compile in by default through `#config(INST_DISABLE, false)`; disable them with `-define:INST_DISABLE=true`. No current entrypoint starts or prints the instrumentation profile.
- `docs/research/tiger-style.md` is research with selectively proposed adaptations, not an executable or blanket style policy; it explicitly says not all TigerBeetle rules apply here.
