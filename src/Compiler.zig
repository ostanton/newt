const std = @import("std");
const ast = @import("ast.zig");
const Bytecode = @import("Bytecode.zig");
const Instruction = Bytecode.Instruction;
const Constant = Bytecode.Constant;

instructions: std.ArrayList(Instruction),
constants: std.ArrayList(Constant),

const Self = @This();

pub const init: Self = .{
    .instructions = .empty,
    .constants = .empty,
};

pub fn visitClass(self: *Self, allocator: std.mem.Allocator, class: ast.ClassDecl) !void {
    _ = self;
    _ = allocator;
    _ = class;
}

pub fn visitExpression(self: *Self, allocator: std.mem.Allocator, expr: ast.Expression) !void {
    _ = self;
    _ = allocator;
    _ = expr;
}

pub fn visitLiteral(self: *Self, allocator: std.mem.Allocator, literal: ast.Literal) !void {
    switch (literal) {
        .ident => |ident| try self.instructions.append(allocator, .{ .ident = ident }),
    }
}

pub fn bytecode(self: Self, allocator: std.mem.Allocator) !Bytecode {
    return .{
        .instructions = try self.instructions.toOwnedSlice(allocator),
        .constants = try self.constants.toOwnedSlice(allocator),
    };
}
