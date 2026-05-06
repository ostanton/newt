const std = @import("std");

pub const Instruction = union(enum) {
    push_i32: i32,
    push_f32: f32,
    add_i32,
    sub_i32,
    mul_i32,
    div_i32,
    add_f32,
    sub_f32,
    mul_f32,
    div_f32,
    print_i32,
    print_f32,

    pub const OpCode = std.meta.Tag(Instruction);
};
