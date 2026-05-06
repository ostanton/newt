const std = @import("std");
const Bytecode = @import("Bytecode.zig");
const Instruction = Bytecode.Instruction;

code: []const Instruction,
ip: usize,
stack: [1024]u8,
sp: usize,

const Self = @This();

pub const Error = error{
    StackUnderflow,
    StackOverflow,
    DivideByZero,
};

pub fn init(code: []const Instruction) Self {
    return .{
        .code = code,
        .ip = 0,
        .stack = @splat(0),
        .sp = 0,
    };
}

pub fn execute(self: *Self, instr: Instruction) Error!void {
    switch (instr) {
        .push_i32 => |int| try self.push(&std.mem.toBytes(int)),
        .push_f32 => |float| try self.push(&std.mem.toBytes(float)),
        .add_i32 => {
            const b = try self.popTyped(i32);
            const a = try self.popTyped(i32);
            try self.pushTyped(a + b);
        },
        .sub_i32 => {
            const b = try self.popTyped(i32);
            const a = try self.popTyped(i32);
            try self.pushTyped(a - b);
        },
        .mul_i32 => {
            const b = try self.popTyped(i32);
            const a = try self.popTyped(i32);
            try self.pushTyped(a * b);
        },
        .div_i32 => {
            const b = try self.popTyped(i32);
            const a = try self.popTyped(i32);
            if (b == 0) {
                return Error.DivideByZero;
            }
            try self.pushTyped(@divFloor(a, b));
        },
        .add_f32 => {
            const b = try self.popTyped(f32);
            const a = try self.popTyped(f32);
            try self.pushTyped(a + b);
        },
        .sub_f32 => {
            const b = try self.popTyped(f32);
            const a = try self.popTyped(f32);
            try self.pushTyped(a - b);
        },
        .mul_f32 => {
            const b = try self.popTyped(f32);
            const a = try self.popTyped(f32);
            try self.pushTyped(a * b);
        },
        .div_f32 => {
            const b = try self.popTyped(f32);
            const a = try self.popTyped(f32);
            try self.pushTyped(a / b);
        },
        .print_i32 => std.log.info("Print i32: {}", .{try self.getTopTyped(i32)}),
        .print_f32 => std.log.info("Print f32: {}", .{try self.getTopTyped(f32)}),
    }
}

fn push(self: *Self, bytes: []const u8) Error!void {
    if (self.sp + bytes.len > self.stack.len) {
        return Error.StackOverflow;
    }

    const target = self.stack[self.sp .. self.sp + bytes.len];
    @memcpy(target, bytes);
    self.sp += bytes.len;
}

fn pushTyped(self: *Self, value: anytype) Error!void {
    try self.push(&std.mem.toBytes(value));
}

fn pop(self: *Self, size: usize) Error![]u8 {
    if (self.sp < size) {
        return Error.StackUnderflow;
    }

    const old_sp = self.sp;
    self.sp -= size;
    return self.stack[self.sp..old_sp];
}

fn popTyped(self: *Self, comptime T: type) Error!T {
    return std.mem.bytesToValue(T, try self.pop(@sizeOf(T)));
}

fn getTop(self: *Self, size: usize) Error![]u8 {
    if (self.sp < size) {
        return Error.StackUnderflow;
    }

    return self.stack[self.sp - size .. self.sp];
}

fn getTopTyped(self: *Self, comptime T: type) Error!T {
    return std.mem.bytesToValue(T, try self.getTop(@sizeOf(T)));
}
