#include "cgen.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>

int main(void) {
    Cgen_example_Object_Id id = 7;
    Cgen_example_Object *object = cgen_example_object_new(id);
    assert(object != NULL);
    assert(cgen_example_object_kind(object, Cgen_example_Kind_Ready, Cgen_example_Flags_A) == 9);

    uint8_t bytes[] = {1, 2, 3, 4};
    Cgen_example_Slice_u8 slice = {bytes, 4};
    assert(cgen_example_sum_bytes(slice) == 10);

    int32_t values[] = {2, 3, 5};
    Cgen_example_Slice_i32 varargs = {values, 3};
    assert(cgen_example_sum_variadic(varargs) == 10);
    assert(cgen_example_sum_with_flags(1, 2, varargs, Cgen_example_Flags_B) == 15);
    assert(cgen_example_sum_variadic((Cgen_example_Slice_i32){NULL, 0}) == 0);

    const uint8_t text[] = {'o', 0, 'k'};
    Cgen_example_String input = {text, 3};
    Cgen_example_String output = cgen_example_echo_bytes(input);
    assert(output.data == text && output.len == 3 && memcmp(output.data, text, 3) == 0);

    Cgen_example_Slice_u8 identity = cgen_example_identity_bytes(slice);
    assert(identity.len == 4 && identity.data[3] == 4);

    Cgen_example_pair_string_bytes_Result pair = cgen_example_pair_string_bytes(input, slice);
    assert(pair.r0.len == 3 && pair.r1.len == 4 && pair.r1.data[0] == 1);

    Cgen_example_Member members[] = {{0, 7}, {8, 11}};
    Cgen_example_Record record = {input, {members, 2}, {2}};
    Cgen_example_Record copied = cgen_example_record_identity(record);
    assert(copied.name.data == text && copied.members.data == members);
    assert(copied.summary.count == 2 && copied.members.data[1].id == 11);
    assert(cgen_example_member_sum(record.members) == 18);

    Cgen_example_Padded padded = {1, 0x1020304050607080ULL};
    Cgen_example_Padded padded_out = cgen_example_move_padded(padded);
    assert(padded_out.a == padded.a && padded_out.b == padded.b);

    Cgen_example_Nested nested = {padded, 9};
    Cgen_example_Nested nested_out = cgen_example_move_nested(nested);
    assert(nested_out.inner.b == nested.inner.b && nested_out.count == 9);

    Cgen_example_split_Result result = cgen_example_split(4);
    assert(result.r0 == 4 && result.r1 == 8);

    cgen_example_object_free(object);
    return 0;
}
