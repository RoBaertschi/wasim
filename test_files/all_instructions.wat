;; Decoder coverage fixture for every instruction supported by wasim.
;;
;; This intentionally relies on the polymorphic stack after `unreachable`.
;; Its purpose is binary decoding coverage, not meaningful execution.
(module
  (type $empty (func))
  (table 1 funcref)
  (memory 1)
  (global $mutable_i32 (mut i32) (i32.const 0))

  (func (type $empty) (local i32)
    ;; Control instructions.
    unreachable
    nop
    block
      nop
    end
    loop
      nop
    end
    if
      nop
    else
      nop
    end
    br 0
    br_if 0
    br_table 0 0
    return
    call 0
    call_indirect (type $empty)

    ;; Parametric and variable instructions.
    drop
    select
    local.get 0
    local.set 0
    local.tee 0
    global.get $mutable_i32
    global.set $mutable_i32

    ;; Memory instructions. Non-default alignments and offsets exercise both
    ;; memarg immediates; the module is never intended to execute.
    i32.load offset=1 align=2
    drop
    i64.load offset=2 align=4
    drop
    f32.load offset=3 align=2
    drop
    f64.load offset=4 align=4
    drop
    i32.load8_s offset=5
    drop
    i32.load8_u offset=6
    drop
    i32.load16_s offset=7 align=2
    drop
    i32.load16_u offset=8 align=2
    drop
    i64.load8_s offset=9
    drop
    i64.load8_u offset=10
    drop
    i64.load16_s offset=11 align=2
    drop
    i64.load16_u offset=12 align=2
    drop
    i64.load32_s offset=13 align=4
    drop
    i64.load32_u offset=14 align=4
    drop
    i32.store offset=15 align=2
    i64.store offset=16 align=4
    f32.store offset=17 align=2
    drop
    f64.store offset=18 align=4
    drop
    i32.store8 offset=19
    i32.store16 offset=20 align=2
    i64.store8 offset=21
    i64.store16 offset=22 align=2
    i64.store32 offset=23 align=4
    memory.size
    drop
    memory.grow
    drop

    ;; Constants and comparisons.
    i32.const -123456
    drop
    i64.const -1234567890123
    drop
    f32.const -0x1.921fb6p+1
    drop
    f64.const 0x1.921fb54442d18p+1
    drop
    i32.eqz
    drop
    i32.eq
    drop
    i32.ne
    drop
    i32.lt_s
    drop
    i32.lt_u
    drop
    i32.gt_s
    drop
    i32.gt_u
    drop
    i32.le_s
    drop
    i32.le_u
    drop
    i32.ge_s
    drop
    i32.ge_u
    drop
    i64.eqz
    drop
    i64.eq
    drop
    i64.ne
    drop
    i64.lt_s
    drop
    i64.lt_u
    drop
    i64.gt_s
    drop
    i64.gt_u
    drop
    i64.le_s
    drop
    i64.le_u
    drop
    i64.ge_s
    drop
    i64.ge_u
    drop
    f32.eq
    drop
    f32.ne
    drop
    f32.lt
    drop
    f32.gt
    drop
    f32.le
    drop
    f32.ge
    drop
    f64.eq
    drop
    f64.ne
    drop
    f64.lt
    drop
    f64.gt
    drop
    f64.le
    drop
    f64.ge
    drop

    ;; Integer numeric instructions.
    i32.clz
    drop
    i32.ctz
    drop
    i32.popcnt
    drop
    i32.add
    drop
    i32.sub
    drop
    i32.mul
    drop
    i32.div_s
    drop
    i32.div_u
    drop
    i32.rem_s
    drop
    i32.rem_u
    drop
    i32.and
    drop
    i32.or
    drop
    i32.xor
    drop
    i32.shl
    drop
    i32.shr_s
    drop
    i32.shr_u
    drop
    i32.rotl
    drop
    i32.rotr
    drop
    i64.clz
    drop
    i64.ctz
    drop
    i64.popcnt
    drop
    i64.add
    drop
    i64.sub
    drop
    i64.mul
    drop
    i64.div_s
    drop
    i64.div_u
    drop
    i64.rem_s
    drop
    i64.rem_u
    drop
    i64.and
    drop
    i64.or
    drop
    i64.xor
    drop
    i64.shl
    drop
    i64.shr_s
    drop
    i64.shr_u
    drop
    i64.rotl
    drop
    i64.rotr
    drop

    ;; Floating-point numeric instructions.
    f32.abs
    drop
    f32.neg
    drop
    f32.ceil
    drop
    f32.floor
    drop
    f32.trunc
    drop
    f32.nearest
    drop
    f32.sqrt
    drop
    f32.add
    drop
    f32.sub
    drop
    f32.mul
    drop
    f32.div
    drop
    f32.min
    drop
    f32.max
    drop
    f32.copysign
    drop
    f64.abs
    drop
    f64.neg
    drop
    f64.ceil
    drop
    f64.floor
    drop
    f64.trunc
    drop
    f64.nearest
    drop
    f64.sqrt
    drop
    f64.add
    drop
    f64.sub
    drop
    f64.mul
    drop
    f64.div
    drop
    f64.min
    drop
    f64.max
    drop
    f64.copysign
    drop

    ;; Conversions and reinterpretations.
    i32.wrap_i64
    drop
    i32.trunc_f32_s
    drop
    i32.trunc_f32_u
    drop
    i32.trunc_f64_s
    drop
    i32.trunc_f64_u
    drop
    i64.extend_i32_s
    drop
    i64.extend_i32_u
    drop
    i64.trunc_f32_s
    drop
    i64.trunc_f32_u
    drop
    i64.trunc_f64_s
    drop
    i64.trunc_f64_u
    drop
    f32.convert_i32_s
    drop
    f32.convert_i32_u
    drop
    f32.convert_i64_s
    drop
    f32.convert_i64_u
    drop
    f32.demote_f64
    drop
    f64.convert_i32_s
    drop
    f64.convert_i32_u
    drop
    f64.convert_i64_s
    drop
    f64.convert_i64_u
    drop
    f64.promote_f32
    drop
    i32.reinterpret_f32
    drop
    i64.reinterpret_f64
    drop
    f32.reinterpret_i32
    drop
    f64.reinterpret_i64
    drop
    unreachable))
