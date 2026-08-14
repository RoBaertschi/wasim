# TigerStyle: summary and practical takeaways

Source: TigerBeetle's official
[`TIGER_STYLE.md`](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md),
reviewed 2026-08-14. The document evolves on `main`, so the links below identify the relevant
sections rather than an immutable revision.

## Summary

TigerStyle treats style as system design, not cosmetic consistency. It ranks its goals as safety,
performance, then developer experience. Simplicity is the difficult result of repeated design work,
not permission to skip it, and the stated "zero technical debt" policy favors resolving known
structural risks before shipping.
([design goals and simplicity](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#why-have-style),
[technical debt](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#technical-debt))

### Safety

- Make control flow simple and explicit, avoid recursion, keep abstractions few and domain-shaped,
  and impose explicit bounds on loops, queues, and other resources.
- Prefer fixed-width integer types. Treat assertions as executable contracts for arguments,
  results, invariants, and compile-time relationships; check both valid and invalid spaces, and
  place paired checks on opposite sides of important boundaries.
- Separate programmer errors (assert and stop) from expected operational errors (handle them), and
  test error paths as seriously as successful paths.
- Bound memory up front and avoid runtime allocation after initialization in TigerBeetle's domain.
  Keep variables narrowly scoped, functions to at most 70 lines, control flow in parent functions,
  and calculation-oriented leaf helpers pure.
- Prefer positive conditions, split compound conditions and assertions, make library options
  explicit at call sites, and explain the reason behind decisions.

Source: [Safety](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#safety).

### Performance

- Include performance in the design phase with rough estimates for network, disk, memory, and CPU,
  considering both bandwidth and latency.
- Optimize the slowest effective resource first, accounting for frequency; separate control and
  data planes and batch work to amortize costs and keep execution predictable.
- Make hot loops easy for both humans and compilers to understand by isolating them in standalone
  functions with simple arguments and little hidden state.

Source: [Performance](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#performance).

### Developer experience

- Use precise domain nouns and verbs, avoid abbreviations, encode units and qualifiers in names,
  and do not reuse one term for different concepts. Arrange source top-down in reading order.
- Prevent ambiguous calls with named option structures; simplify signatures and return types to
  reduce branching that spreads through callers.
- Avoid aliases and duplicate state. Initialize large values in place when stable addresses matter,
  and calculate or validate values close to where they are used.
- Distinguish indexes, counts, and byte sizes in names and conversions, and express division
  rounding explicitly.
- Write comments and commit messages that preserve why and how, not merely what the code does.

Source: [Developer Experience](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#developer-experience).

### Numeric and operational rules

The project mandates formatting, four-space indentation, a 100-column maximum, braces except for
single-line conditionals, no dependencies beyond Zig, and a small standardized toolset. These are
TigerBeetle-specific policy choices rather than universal rules.
([Style By The Numbers](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#style-by-the-numbers),
[Dependencies](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#dependencies),
[Tooling](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#tooling))

## Practical application across a codebase

The following recommendations are language-portable adaptations, not a claim that TigerBeetle's
project-specific conventions should apply everywhere:

1. **Start with boundaries.** For every loop, queue, allocation, input length, and retry path, write
   down the maximum. Use an assertion where exceeding it means a programmer/design error; return an
   error where it is valid external input or an expected operating condition.
2. **Make invariants visible at transitions.** Assert a value before serialization or crossing an
   API boundary and validate/assert it again after deserialization or on the receiving side. Split
   assertions so failures identify the exact broken property.
3. **Audit numeric names.** Rename vague `len`, `size`, and `offset` values to forms such as
   `instruction_count`, `buffer_size_bytes`, or `memory_offset_bytes`. Prefer fixed-width types for
   formats, protocols, and persistent state; convert deliberately at host-memory boundaries.
4. **Reshape long functions by responsibility.** Keep branching and state transitions in one
   coordinator. Extract bounded loops and calculations into helpers that return proposed values
   instead of mutating shared state.
5. **Estimate before optimizing.** For a hot path, record input scale, calls per operation, bytes
   moved, allocation count, and expected latency. Then batch or simplify the resource that dominates
   the estimate; profile afterward to test the model.
6. **Reduce hidden choices.** Pass important policy explicitly rather than depending on defaults,
   especially for allocators, byte order, capacity, rounding, ownership, and failure behavior.
7. **Review lifetimes and aliases.** Keep one authoritative representation of each state fact,
   narrow variable scope, perform checks near use, and use pointer parameters intentionally for
   large or identity-bearing values.
8. **Adopt policy selectively.** The assertion discipline, bounds, naming, explicitness, batching,
   and resource estimates generalize well. Static startup-only allocation, zero dependencies, exact
   70/100-line limits, and a single-language toolchain are domain/team tradeoffs to evaluate rather
   than copy mechanically.

These adaptations follow the source's safety, performance, naming, cache-invalidation, and
off-by-one guidance:
[Safety](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#safety),
[Performance](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#performance),
[Naming Things](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#naming-things),
[Cache Invalidation](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#cache-invalidation),
and [Off-By-One Errors](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md#off-by-one-errors).
