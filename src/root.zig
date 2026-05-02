const std = @import("std");
const Parser = @import("Parser.zig");

pub const ast = @import("ast.zig");

/// Layout DSL parsing
pub const layout = struct {
    pub fn parseString(allocator: std.mem.Allocator, src: []const u8) Parser.Error!ast.Widget {
        var parser: Parser = .init(src);
        return parser.parseWidget(allocator);
    }
};

/// Scripting language compilation
pub const script = struct {};
