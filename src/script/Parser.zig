const std = @import("std");
const Lexer = @import("../Lexer.zig");
const Token = @import("../Token.zig");

lexer: Lexer,
current: Token,
allocator: std.mem.Allocator,

const Self = @This();
const keywords: std.StaticStringMap(Token.Kind) = .initComptime(.{
    .{ "true", .true_lit },
    .{ "false", .false_lit },
    .{ "bool", .bool_type },
    .{ "float", .float_type },
    .{ "int", .int_type },
    .{ "string", .string_type },
    .{ "func", .func },
    .{ "enum", .@"enum" },
    .{ "class", .class },
    .{ "layout", .layout },
});

const Error = error{};

fn advance(self: *Self) void {
    const lexer = &self.lexer;
    lexer.skipWhitespace();
    self.current = .{};
}
