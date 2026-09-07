# Comment Guide

Use comments to explain behavior, constraints, ownership, and decisions that are not clear from the code itself. Keep comments current and remove them when they only repeat the code.

## Public declarations

Place documentation immediately above the declaration and use `//` comments. Start with a short sentence describing what the declaration does. Write names, parameters, types, enum values, and expressions in backticks.

```odin
// `function_add` adds a function named `name` to an unfrozen module.
//
// `result_type` must currently have type kind `.Result`. A result type carries
// the returned value together with the memory value required by the SSA form.
function_add :: proc(...) ...
```

Document parameters in prose when only one or two have surprising requirements. Use explicit sections for procedures with many non-obvious inputs or outputs:

```odin
// Decodes a module from `data`.
//
// Parameters:
//   data    - Input bytes to decode.
//   errors  - Destination to which decoding errors are appended.
//
// Returns:
//   The decoded module and whether decoding succeeded.
```

Useful optional sections are `Parameters:`, `Returns:`, `Example:`, and `Examples:`. Add them only when they make the contract easier to understand. Separate paragraphs and sections with a blank comment line (`//`).

Use `Note:` for individual qualifications such as complexity, panics, lifetime requirements, or a preferred alternative:

```odin
// Note: This is an O(N) operation.
// Note: The returned slice remains valid until the arena is reset.
// Note: If `index` is out of bounds, this procedure will panic.
```

## Implementation comments

Explain why the implementation takes a particular approach, especially when ownership, concurrency, temporary storage, or a specification requirement is involved. Do not narrate each statement.

Use `NOTE(name):` for information aimed at maintainers, `TODO(name):` for concrete unfinished work, and `WARN:` for a constraint whose violation could easily introduce a bug.

```odin
// NOTE(robin): The map uses the heap because storing its backing allocation in
// the arena would retain obsolete growth allocations until module destruction.
```

Comments inside a procedure should sit directly above the code they explain. Prefer a complete sentence unless a short label makes the code easier to scan.

## Style

- Keep the first sentence useful on its own.
- Describe observable behavior in the present tense.
- State preconditions and ownership explicitly.
- Refer to declarations using their exact names.
- Keep examples short and focused on the contract being demonstrated.
- Wrap long comments to roughly the same width as the surrounding source.
- Avoid duplicating parameter types or other facts already clear from the signature.
