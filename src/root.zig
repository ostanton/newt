const std = @import("std");
const Parser = @import("Parser.zig");
const Compiler = @import("Compiler.zig");

pub const VirtualMachine = @import("VirtualMachine.zig");
pub const ast = @import("ast.zig");

/// Layout DSL parsing
pub const layout = struct {
    pub fn parseString(allocator: std.mem.Allocator, src: []const u8) Parser.Error!ast.Widget {
        var parser: Parser = .init(src, .layout);
        return parser.parseWidget(allocator);
    }
};

/// Scripting language compilation
pub const script = struct {
    pub fn parseString(allocator: std.mem.Allocator, src: []const u8, class_name: []const u8) Parser.Error!ast.ClassDecl {
        var parser: Parser = .init(src, .script);
        return parser.parseClassBody(allocator, class_name);
    }
};
