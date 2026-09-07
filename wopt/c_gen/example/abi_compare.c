#include "cgen.h"
#include <assert.h>

/* Same semantic values through direct and pointer C/Odin calls.
   Padding bytes are deliberately unspecified; only fields are compared. */

int main(void) {
    Cgen_example_Padded value = {3, 99};
    Cgen_example_Padded result = cgen_example_move_padded(value);
    assert(result.a == 3 && result.b == 99);
    cgen_example_move_padded_ptr(&value, &result);
    assert(result.a == 3 && result.b == 99);

    Cgen_example_Nested nested = {value, 9};
    Cgen_example_Nested direct_nested = cgen_example_move_nested(nested);
    assert(direct_nested.inner.b == nested.inner.b && direct_nested.count == 9);
    Cgen_example_Nested pointer_nested = {0};
    cgen_example_move_nested_ptr(&nested, &pointer_nested);
    assert(pointer_nested.inner.b == nested.inner.b && pointer_nested.count == 9);

    Cgen_example_Mixed mixed = {1.25f, 9.5};
    Cgen_example_Mixed mixed_result = cgen_example_mixed_identity(mixed);
    assert(mixed_result.a == mixed.a && mixed_result.b == mixed.b);
    cgen_example_mixed_pointer(&mixed, &mixed_result);
    assert(mixed_result.a == mixed.a && mixed_result.b == mixed.b);

    Cgen_example_Tail tail = {9.5, 1.25f};
    Cgen_example_Tail tail_result = cgen_example_tail_identity(tail);
    assert(tail_result.a == tail.a && tail_result.b == tail.b);
    cgen_example_tail_pointer(&tail, &tail_result);
    assert(tail_result.a == tail.a && tail_result.b == tail.b);
    return 0;
}
