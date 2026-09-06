# API design scratch book

## Open questions

- [ ] We always return a memory in a function, should the user have to handle that?

## V2

```odin

main :: proc() {
    m := module_new()
    defer module_free(m)

    type_i32 := type_get_builtin(m, .I32)

    func_id := function_add(m, "main", /* result */ type_i32, /* parameters */ type_i32, type_i32, flags = {})

    module_freeze_for_build(m)
    ensure(module_is_frozen(m))

    tbctx := thread_build_context_new(m)
    defer thread_build_context_free(m, tbctx)

    {
        build_function_begin(tbctx, func_id)

        block_id := build_begin_block(tbctx, .Exit)
        memory_value := build_value_init_memory(tbctx)
        const_value  := build_value_const32(tbctx, 0)
        return_value := build_value_memory_tuple_make(tbctx, type_memory_tuple(m, type_i32), const_value, memory_value)

        // Option 1
        build_block_set_control_value(tbctx, block_id, return_value)
        build_end_block(tbctx, block_id)
        // Option 2
        build_end_block_with_control_value(tbctx, block_id, return_value)


        build_set_start_block(tbctx, block_id)

        build_function_end(tbctx)
    }
}

```

## V1

```odin

main :: proc() {
    m := module_new()
    defer module_free()

    type_i32 := type_get_builtin(m, .I32)

    func_id := function_add(m, "main", /* result */ type_i32, /* parameters */ type_i32, type_i32, flags = {})

    module_freeze(m)
    ensure(._Frozen in function_get(m, func_id).flags)

    tbctx := thread_build_context_new(m)
    defer thread_build_context_free(m, thread_build_ctx)

    {
        build_function_begin(tbctx, func_id)

        block_id := build_begin_exit_block(tbctx)
        memory_value := build_value(tbctx, value_init_memory())
        const_value  := build_value(tbctx, value_const32(0))
        return_value := build_value(tbctx, value_memory_tuple_make(memory_tuple(m, type_i32), const_value, memory_value))
        build_end_exit_block(tbctx, block_id, return_value)

        build_start_block(tbctx, block_id)

        build_function_end(tbctx)
    }
}

```
