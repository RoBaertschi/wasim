# Repository Guide

## Project Direction

- Wasim is an Odin WebAssembly runtime under development. The first milestone is an interpreted runtime implementing WebAssembly Core Specification 1.0.
- Currently, binary decoding and the shared module representation exist, and WAT parsing is in progress. Validation, interpretation, WASI, and JIT compilation are not implemented yet.
- The Core 1.0 milestone is complete when the interpreted runtime passes the official Core 1.0 specification test suite. WAT parsing supports that suite because its WAST scripts embed and extend WAT. Keep the binary reader, text parser, and runtime model aligned to Core 1.0 until then.
- After Core 1.0, target WASI Preview 1 only; later WASI previews are outside the plan. Then target Core 2.0, evaluate Core 3.0 before committing to it, add WASIX, and add JIT compilation through a custom backend with LLVM as a possible additional backend.

## Verification

- Complete verification requires all three commands: `odin test . -all-packages -vet -warnings-as-errors`, `odin check examples/decoder -vet -warnings-as-errors`, and `odin check task -vet -warnings-as-errors`. The root is library package `wasim`, so `odin check .` fails for lack of `main`.
- For a focused run, use `odin test base -vet -warnings-as-errors` for the `base` package or `odin test base -vet -warnings-as-errors -- -tests:arena_lifecycle_test` for one test. Test filters are test-runner arguments after `--`.
- Build outside the worktree with `odin build examples/decoder -out:/tmp/wasim-decoder`; smoke-test with `/tmp/wasim-decoder test_files/empty.wasm -thread-count:2`. Application options use colon syntax.
- Treat `task/task.odin` as type-checkable but not as the parser runner: it invokes `odin run .`, which targets the root library and fails for lack of `main`.
- The repository defines no formatter, CI workflow, code-generation command, or documented regeneration path for checked-in `.wasm` fixtures.

## Package Layout

- The root `.odin` files form library package `wasim`; `bin_read` and the parallel WASM reader are in `wasim_binary.odin`. The CLI entrypoint is `examples/decoder/decoder.odin`.
- `base/` is imported as package `wasim_base` and aliased as `B` by the executable. Its `@test` procedures live in implementation files.
- `base/arena.odin` implements the project's custom virtual-memory arena; do not confuse it with `core:mem/virtual.Arena`, which is also used by some base utilities.

## Parallel Reader

- Give every reader thread a `B.Lane_Ctx` and call `B.lane_select_ctx` before any lane helper. Set the shared `sync.Barrier` participant count to exactly the lane count.
- Lane 0 scans the module header and section table, then `B.lane_sync_value` broadcasts shared values. Non-code sections and function bodies are distributed with lane ranges.
- `B.lane_sync_value` only supports values no larger than `u128` and deliberately performs two barrier waits around the shared scratch word.
- The shared `sync.One_Shot_Event` signals that lane 0 completed `bin_read_entry_point`; worker completion requires `bin_read` to join every created thread.

## Project-Specific Behavior

- `B.TEMP_ALLOCATOR_GUARD` rolls its per-thread arena back at scope exit. Copy surviving pointed-to data into a longer-lived arena before exit.
- Instrumented scopes compile in by default through `#config(INST_DISABLE, false)`; disable them with `-define:INST_DISABLE=true`. No current entrypoint starts or prints the instrumentation profile.
- Treat `docs/research/tiger-style.md` as research and selective proposals, not a blanket repository policy.
