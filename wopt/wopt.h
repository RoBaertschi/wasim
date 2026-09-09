#ifndef WOPT_H
#define WOPT_H

// FFI Types

#ifndef WOPT_INTEGER_TYPES
#include <stdint.h>
#include <stddef.h>

typedef uint8_t  wopt_u8;
typedef uint16_t wopt_u16;
typedef uint32_t wopt_u32;
typedef uint64_t wopt_u64;

typedef int8_t  wopt_i8;
typedef int16_t wopt_i16;
typedef int32_t wopt_i32;
typedef int64_t wopt_i64;

typedef size_t   wopt_uint;
typedef intptr_t wopt_int;

#endif // WOPT_INTEGER_TYPES

typedef wopt_u8 wopt_bool;

typedef struct wopt_string {
    wopt_u8 const *data;
    wopt_int      len;
} wopt_string;

// Module API
typedef void *Wopt_Module;

typedef wopt_uint Wopt_Type_Id;
typedef wopt_u32  Wopt_Function_Id;

typedef struct Wopt_Type_Member {
    wopt_int    offset;
    Wopt_Type_Id type;
} Wopt_Type_Member;

typedef wopt_u32 Wopt_Function_Flags;

#define WOPT_FUNCTION_FLAG_NONE          ((Wopt_Function_Flags)0)
#define WOPT_FUNCTION_FLAG_ALWAYS_INLINE ((Wopt_Function_Flags)1 << 0)
#define WOPT_FUNCTION_FLAG_NEVER_INLINE  ((Wopt_Function_Flags)1 << 1)

Wopt_Module wopt_module_new(void);
void wopt_module_free(Wopt_Module module);

Wopt_Type_Id wopt_type_none(Wopt_Module module);
Wopt_Type_Id wopt_type_i32(Wopt_Module module);
Wopt_Type_Id wopt_type_mem(Wopt_Module module);
Wopt_Type_Id wopt_type_struct_simple(
    Wopt_Module module,
    Wopt_Type_Id *members,
    wopt_int member_count);
Wopt_Type_Id wopt_type_struct(
    Wopt_Module module,
    wopt_int size,
    wopt_int align,
    Wopt_Type_Member *members,
    wopt_int member_count);

Wopt_Function_Id wopt_function_add(
    Wopt_Module module,
    wopt_string name,
    Wopt_Type_Id result_type,
    Wopt_Type_Id *parameters,
    wopt_int parameter_count,
    Wopt_Function_Flags flags);

void wopt_module_freeze_for_build(Wopt_Module module);
wopt_bool wopt_module_is_frozen(Wopt_Module module);

// Builder API

typedef void *Wopt_Thread_Build_Context;

typedef wopt_u32 Wopt_Block_Id;
typedef wopt_u32 Wopt_Value_Id;

typedef wopt_int Wopt_Block_Kind;

#define WOPT_BLOCK_KIND_EXIT ((Wopt_Block_Kind)0)

typedef void (*Wopt_SSA_Verify_Error_Callback)(
    Wopt_Thread_Build_Context tbctx,
    void *user_data,
    Wopt_Function_Id function_id,
    wopt_string message);

Wopt_Thread_Build_Context wopt_thread_build_context_new(
    Wopt_Module module,
    Wopt_SSA_Verify_Error_Callback error_callback,
    void *user_data);

void wopt_thread_build_context_free(Wopt_Thread_Build_Context tbctx);

void wopt_build_function_begin(
    Wopt_Thread_Build_Context tbctx,
    Wopt_Function_Id function_id);
wopt_int wopt_build_function_end(Wopt_Thread_Build_Context tbctx);

Wopt_Block_Id wopt_build_begin_block(
    Wopt_Thread_Build_Context tbctx,
    Wopt_Block_Kind kind);
void wopt_build_end_block(Wopt_Thread_Build_Context tbctx);
void wopt_build_block_set_control_value(
    Wopt_Thread_Build_Context tbctx,
    Wopt_Value_Id value_id);
void wopt_build_set_start_block(
    Wopt_Thread_Build_Context tbctx,
    Wopt_Block_Id block_id);

Wopt_Value_Id wopt_build_value_get_argument(
    Wopt_Thread_Build_Context tbctx,
    wopt_int parameter_index);
Wopt_Value_Id wopt_build_value_argument(
    Wopt_Thread_Build_Context tbctx,
    wopt_u32 parameter_index);
Wopt_Value_Id wopt_build_value_init_memory(Wopt_Thread_Build_Context tbctx);
Wopt_Value_Id wopt_build_value_const32(
    Wopt_Thread_Build_Context tbctx,
    wopt_u32 value);
Wopt_Value_Id wopt_build_value_return(
    Wopt_Thread_Build_Context tbctx,
    Wopt_Value_Id value_id);

Wopt_Type_Id wopt_build_type_none(Wopt_Thread_Build_Context tbctx);
Wopt_Type_Id wopt_build_type_i32(Wopt_Thread_Build_Context tbctx);
Wopt_Type_Id wopt_build_type_mem(Wopt_Thread_Build_Context tbctx);
Wopt_Type_Id wopt_build_type_struct_simple(
    Wopt_Thread_Build_Context tbctx,
    Wopt_Type_Id *members,
    wopt_int member_count);
Wopt_Type_Id wopt_build_type_struct(
    Wopt_Thread_Build_Context tbctx,
    wopt_int size,
    wopt_int align,
    Wopt_Type_Member *members,
    wopt_int member_count);

#endif // WOPT_H
