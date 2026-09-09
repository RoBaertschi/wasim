#include "wopt.h"

#include <assert.h>

static wopt_int verify_error_count;

static void verify_error(
    Wopt_Thread_Build_Context tbctx,
    void *user_data,
    Wopt_Function_Id function_id,
    wopt_string message) {
    (void)tbctx;
    (void)user_data;
    (void)function_id;
    (void)message;
    verify_error_count += 1;
}

int main(void) {
    Wopt_Module m = wopt_module_new();
    Wopt_Type_Id none = wopt_type_none(m);
    Wopt_Type_Id i32 = wopt_type_i32(m);
    Wopt_Type_Id mem = wopt_type_mem(m);
    Wopt_Type_Id struct_members[] = {i32, i32};
    Wopt_Type_Id pair = wopt_type_struct_simple(m, struct_members, 2);
    Wopt_Type_Member explicit_members[] = {{0, i32}, {4, i32}};
    Wopt_Type_Id explicit_pair =
        wopt_type_struct(m, 8, 4, explicit_members, 2);
    Wopt_Type_Id parameters[] = {i32, i32};
    wopt_string name = {(wopt_u8 *)"main", 4};
    Wopt_Function_Id function_id = wopt_function_add(
        m,
        name,
        i32,
        parameters,
        2,
        WOPT_FUNCTION_FLAG_NONE);

    wopt_module_freeze_for_build(m);
    assert(wopt_module_is_frozen(m));

    Wopt_Thread_Build_Context tbctx =
        wopt_thread_build_context_new(m, verify_error, NULL);

    assert(wopt_build_type_none(tbctx) == none);
    assert(wopt_build_type_i32(tbctx) == i32);
    assert(wopt_build_type_mem(tbctx) == mem);
    assert(wopt_build_type_struct_simple(tbctx, struct_members, 2) == pair);
    assert(wopt_build_type_struct(tbctx, 8, 4, explicit_members, 2) == explicit_pair);

    wopt_build_function_begin(tbctx, function_id);
    Wopt_Block_Id block = wopt_build_begin_block(tbctx, WOPT_BLOCK_KIND_EXIT);
    Wopt_Value_Id argument_0 = wopt_build_value_argument(tbctx, 0);
    (void)wopt_build_value_argument(tbctx, 1);
    assert(wopt_build_value_get_argument(tbctx, 0) == argument_0);
    Wopt_Value_Id memory = wopt_build_value_init_memory(tbctx);
    Wopt_Value_Id constant = wopt_build_value_const32(tbctx, 69);
    (void)wopt_build_value_return(tbctx, constant);
    wopt_build_block_set_control_value(tbctx, memory);
    wopt_build_end_block(tbctx);
    wopt_build_set_start_block(tbctx, block);

    assert(wopt_build_function_end(tbctx) == 0);
    assert(verify_error_count == 0);

    wopt_thread_build_context_free(tbctx);
    wopt_module_free(m);
}
