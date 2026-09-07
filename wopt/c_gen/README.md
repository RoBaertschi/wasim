# Odin C binding generator prototype

Run from this directory (Odin requires host access in the development container):

```sh
odin run . -vet -warnings-as-errors -out:c_gen.bin -- example
```

It writes the marked `cgen.h` and `cgen.odin` files beside the annotated
package. Existing unmarked files are left untouched and cause generation to
fail. Both destinations are checked before either is replaced. Output is
deterministic, and marked generated files are excluded before parsing.

Annotate procedures and exposed named types with `@(tag="cabi")`. Use
`@(tag="cabi_opaque")` for structs exposed only through pointers; their fields
remain private. The generator reads the whole package, without resolving imports
or type-checking it. Input must otherwise be a valid Odin package.

The header and wrappers share the source directory. C names follow `wopt.h`:
`Package_Type` and `package_procedure`. Wrappers use the C calling convention and
initialize `runtime.default_context()` before calling the original procedure.

Strings and slices are borrowed `data`/`len` structs. Strings may contain zero
bytes. Variadics use the same slice representation; defaulted parameters are
mandatory in C. APIs retaining data must copy it, and returned data keeps its
original lifetime. Lengths must fit Odin `int`, and nonempty slices must point
to valid storage. The generated slice pointers are const-qualified in C; this
does not enforce immutability in the called Odin procedure.

Distinct integer IDs, enums and flags use matching integer typedefs. Implicit
enum storage is Odin `int`; implicit bit-set storage follows the enum range.
Named and inline enum bit sets are supported, with integer-literal enum values.
Value structs retain field order, including nested structs, `using` fields and
slice fields. Multiple returns use generated result structs.

The prototype diagnoses unsupported selected signatures: unions (including
raw unions), callbacks, polymorphism, overloads, conditional `when` exports,
imported or unannotated types, arrays, packed/custom-aligned structs, and plain
type aliases. Inferred defaults are supported for typed compound literals such
as `flags := Flags{}`. Other inferred types require explicit annotations.
It does not evaluate build tags or platform-specific file selection; use a
single-platform input package. This is a syntax-based prototype, not an Odin
semantic checker.

## Eight example scenarios

`example/example.odin`, `example/records.odin`, and `example/test.c` cover:

1. Opaque object allocation and release.
2. Scalars and distinct object IDs.
3. Enums and flags, including inferred defaults and nonzero enum lower bounds.
4. Borrowed strings, including embedded zero bytes.
5. Slices and variadics, including empty input and trailing defaulted flags.
6. Nested value records with borrowed slices and grouped parameters.
7. Multiple returns, including strings and slices.
8. Padded structs, compared through direct and pointer calls in `abi_compare.c`.

## Verification

From this directory:

```sh
odin test . -vet -warnings-as-errors -out:tests.bin
odin run . -vet -warnings-as-errors -out:c_gen.bin -- example
odin build example -build-mode:shared -vet -warnings-as-errors -out:example/example.so
cc -std=c11 -Wall -Wextra -Werror example/test.c example/example.so -o example/test.bin
./example/test.bin
cc -std=c11 -Wall -Wextra -Werror example/abi_compare.c example/example.so -o example/abi_compare.bin
./example/abi_compare.bin
```

The direct and pointer ABI probes both pass on Linux x86-64 with the installed
Odin `HEAD-c59786c` compiler. They compare semantic fields for integer padding,
nested aggregates, mixed float/double internal padding, and trailing padding.
They do not assume padding bytes are zero or compare structs with `memcmp`.
The generator keeps direct aggregate passing; the pointer alternative remains
an explicit example, not a configuration mode. Other compilers, platforms and
custom layouts remain unverified. This comparison checks correctness, not speed.
