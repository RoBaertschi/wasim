# Repository Guide

## Commands

- Type-check with vetting: `odin check . -vet -warnings-as-errors`.
- Run the complete test suite, including imported packages: `odin test . -all-packages`.
- Run only the `base` package tests: `odin test base`.
- Run one test: `odin test base -- -tests:arena_lifecycle_test`. Test filtering is a test-runner argument after `--`, not an Odin compiler flag.
- Build outside the worktree to avoid an untracked binary: `odin build . -out:/tmp/wasim`.
- Smoke-test the parser with `/tmp/wasim test_files/empty.wasm`. Application options use Odin's colon syntax, for example `-thread-count:2`; `-thread-count 2` is parsed incorrectly.
- There is no repo-local task runner, formatter configuration, CI workflow, or code-generation command. The checked-in `.wasm` fixtures have no documented regeneration flow.

## Package Layout

- The root `.odin` files form executable package `wasim`; `main` and the WASM reader are in `wasim_wasm.odin`.
- `base/` is a separate imported package named `wasim_base`, aliased as `B` by the executable. Its `@test` procedures are embedded in implementation files rather than `*_test.odin` files.
- `base/arena.odin` implements the project's custom virtual-memory arena; do not confuse it with `core:mem/virtual.Arena`, which is also used by some base utilities.

## Parallel Reader

- Every reader thread must receive a `B.Lane_Ctx` and call `B.lane_select_ctx` before using lane helpers. The shared `sync.Barrier` participant count must exactly match the lane count.
- Lane 0 parses the module header and section table, then `B.lane_sync_value` broadcasts shared values. Sections are distributed by `B.lane_range`; all lanes execute `read_module`.
- `B.lane_sync_value` only supports values no larger than `u64` and deliberately performs two barrier waits around the shared scratch word.
- The shared `sync.One_Shot_Event` means lane 0 has completed `read_module`; it does not count worker completion. `main` still joins every created thread afterward.

## Project-Specific Behavior

- `B.TEMP_ALLOCATOR_GUARD` uses per-thread arenas and rolls allocations back at scope exit. Preserve pointed-to data in a longer-lived arena before leaving that scope.
- Instrumentation is enabled by default through `#config(INST_DISABLE, false)`, and `main` prints profiling output. Disable instrumented scopes at compile time with `-define:INST_DISABLE=true`.
- `docs/research/tiger-style.md` is research with selectively proposed adaptations, not an executable or blanket style policy; it explicitly says not all TigerBeetle rules apply here.
