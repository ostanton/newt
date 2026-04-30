const std = @import("std");

/// Layout DSL parsing
pub const layout = struct {
    pub const ast = @import("layout/ast.zig");
    pub const Parser = @import("layout/Parser.zig");

    pub fn parseFile(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File) Parser.Error!ast.Widget {
        var buffer: [1024]u8 = undefined;
        var file_reader = file.reader(io, &buffer);
        return parseReader(allocator, &file_reader.interface);
    }

    pub fn parseReader(allocator: std.mem.Allocator, reader: *std.Io.Reader) Parser.Error!ast.Widget {
        const src = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(src);
        return parseString(allocator, src);
    }

    pub fn parseString(allocator: std.mem.Allocator, src: []const u8) Parser.Error!ast.Widget {
        var parser: Parser = .init(allocator, src);
        return parser.parseWidget();
    }
};

/// Scripting language compilation
pub const script = struct {
    pub const Parser = @import("script/Parser.zig");
};
