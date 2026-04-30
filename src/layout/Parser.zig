const std = @import("std");
const Lexer = @import("../Lexer.zig");
const Token = @import("../Token.zig");
const ast = @import("ast.zig");

lexer: Lexer,
current: Token,
allocator: std.mem.Allocator,

const Self = @This();
const keywords: std.StaticStringMap(Token.Kind) = .initComptime(.{
    .{ "true", .true_lit },
    .{ "false", .false_lit },
});

pub const Error = error{
    UnexpectedToken,
    InvalidSyntax,

    InvalidCharacter,
    Overflow,
} || std.Io.Reader.LimitedAllocError;

pub fn init(allocator: std.mem.Allocator, src: []const u8) Self {
    var self: Self = .{
        .lexer = .{
            .src = src,
            .pos = 0,
            .line = 1,
            .column = 1,
        },
        .current = undefined,
        .allocator = allocator,
    };
    self.advance();
    return self;
}

pub fn parseWidget(self: *Self) Error!ast.Widget {
    if (!self.check(.ident)) {
        return Error.UnexpectedToken;
    }

    const name = try self.allocator.dupe(u8, self.current.value);
    errdefer self.allocator.free(name);
    self.advance();

    var props_arr: std.ArrayList(ast.Property) = .empty;
    errdefer {
        for (props_arr.items) |*prop| {
            prop.deinit(self.allocator);
        }
        props_arr.deinit(self.allocator);
    }
    while (self.check(.ident)) {
        // Parse property pairs
        try props_arr.append(self.allocator, try self.parseProperty());
    }

    var slots_arr: std.ArrayList(ast.Slot) = .empty;
    errdefer {
        for (slots_arr.items) |*slot| {
            slot.deinit(self.allocator);
        }
        slots_arr.deinit(self.allocator);
    }
    while (self.match(.plus)) {
        try slots_arr.append(self.allocator, try self.parseSlot());
    }

    return .{
        .name = name,
        .properties = props_arr,
        .slots = slots_arr,
    };
}

pub fn parseSlot(self: *Self) Error!ast.Slot {
    var props_arr: std.ArrayList(ast.Property) = .empty;
    errdefer {
        for (props_arr.items) |*prop| {
            prop.deinit(self.allocator);
        }
        props_arr.deinit(self.allocator);
    }
    while (self.check(.ident)) {
        try props_arr.append(self.allocator, try self.parseProperty());
    }

    try self.expect(.left_bracket);
    var widget = try self.parseWidget();
    errdefer widget.deinit(self.allocator);
    try self.expect(.right_bracket);

    return .{
        .properties = props_arr,
        .widget = widget,
    };
}

pub fn parseProperty(self: *Self) Error!ast.Property {
    if (!self.check(.ident)) {
        return Error.UnexpectedToken;
    }

    const key = try self.allocator.dupe(u8, self.current.value);
    errdefer self.allocator.free(key);
    self.advance();

    if (!(self.match(.assign) or self.match(.binding))) {
        // TODO - error, requires assignment of some kind
        return Error.UnexpectedToken;
    }

    return .{
        .key = key,
        .value = try self.parsePropertyValue(),
    };
}

pub fn parsePropertyValue(self: *Self) Error!ast.Property.Value {
    const value: ast.Property.Value = switch (self.current.kind) {
        .ident => .{ .ident = try self.allocator.dupe(u8, self.current.value) },
        .string_lit => .{ .string = try self.allocator.dupe(u8, self.current.value) },
        .float_lit => .{ .float = try std.fmt.parseFloat(f32, self.current.value) },
        .int_lit => .{ .int = try std.fmt.parseInt(i32, self.current.value, 10) },
        .true_lit => .{ .bool = true },
        .false_lit => .{ .bool = false },
        .left_bracket => {
            self.advance();
            var values: std.ArrayList(ast.Property.Value) = .empty;
            errdefer {
                for (values.items) |*v| {
                    v.deinit(self.allocator);
                }
                values.deinit(self.allocator);
            }
            while (!self.check(.right_bracket)) {
                try values.append(self.allocator, try self.parsePropertyValue());
                if (!self.match(.comma)) {
                    break;
                }
            }
            try self.expect(.right_bracket);
            return .{ .tuple = values };
        },
        .left_square => {
            self.advance();
            return .{ .array = try self.parsePropertyValueArray() };
        },
        else => return Error.UnexpectedToken,
    };
    self.advance();
    return value;
}

pub fn parsePropertyValueArray(self: *Self) Error!ast.Property.Value.Array {
    const DynamicPropArray = union(std.meta.Tag(ast.Property.Value.Array)) {
        bool: std.ArrayList(bool),
        float: std.ArrayList(f32),
        int: std.ArrayList(i32),
        string: std.ArrayList([]u8),
    };

    // Setup array to expect the type of its first element
    var dyn_arr: DynamicPropArray = switch (self.current.kind) {
        .true_lit, .false_lit => .{ .bool = .empty },
        .float_lit => .{ .float = .empty },
        .int_lit => .{ .int = .empty },
        .string_lit => .{ .string = .empty },
        else => return Error.UnexpectedToken,
    };
    errdefer {
        switch (dyn_arr) {
            .bool => |*b| b.deinit(self.allocator),
            .float => |*f| f.deinit(self.allocator),
            .int => |*i| i.deinit(self.allocator),
            .string => |*s| {
                for (s.items) |string| {
                    self.allocator.free(string);
                }
                s.deinit(self.allocator);
            },
        }
    }

    while (!self.check(.right_square)) {
        switch (self.current.kind) {
            .true_lit => switch (dyn_arr) {
                .bool => |*b| try b.append(self.allocator, true),
                else => return Error.InvalidSyntax,
            },
            .false_lit => switch (dyn_arr) {
                .bool => |*b| try b.append(self.allocator, false),
                else => return Error.InvalidSyntax,
            },
            .float_lit => switch (dyn_arr) {
                .float => |*f| try f.append(self.allocator, try std.fmt.parseFloat(f32, self.current.value)),
                else => return Error.InvalidSyntax,
            },
            .int_lit => switch (dyn_arr) {
                .int => |*i| try i.append(self.allocator, try std.fmt.parseInt(i32, self.current.value, 10)),
                else => return Error.InvalidSyntax,
            },
            .string_lit => switch (dyn_arr) {
                .string => |*s| try s.append(self.allocator, try self.allocator.dupe(u8, self.current.value)),
                else => return Error.InvalidSyntax,
            },
            else => {},
        }
        self.advance();

        if (!self.match(.comma)) {
            break;
        }
    }

    try self.expect(.right_square);
    return switch (dyn_arr) {
        .bool => |b| .{ .bool = b },
        .float => |f| .{ .float = f },
        .int => |i| .{ .int = i },
        .string => |s| .{ .string = s },
    };
}

fn advance(self: *Self) void {
    const lexer = &self.lexer;
    lexer.skipWhitespace();

    if (lexer.pos >= lexer.src.len) {
        self.current = .{
            .kind = .eof,
            .value = "",
            .line = lexer.line,
            .column = lexer.column,
        };
        return;
    }

    const char = lexer.src[lexer.pos];
    self.current = switch (char) {
        '+' => lexer.makeToken(.plus, "+"),
        '(' => lexer.makeToken(.left_bracket, "("),
        ')' => lexer.makeToken(.right_bracket, ")"),
        '[' => lexer.makeToken(.left_square, "["),
        ']' => lexer.makeToken(.right_square, "]"),
        ',' => lexer.makeToken(.comma, ","),
        '=' => if (lexer.peek()) |c| switch (c) {
            '>' => lexer.makeTokenEx(.binding, "=>", 2, 2),
            else => lexer.makeToken(.assign, "="),
        } else unreachable,
        '"' => blk: {
            lexer.pos += 1;
            lexer.column += 1;
            break :blk lexer.readStringLit();
        },
        else => if (std.ascii.isDigit(char) or char == '-') lexer.readNumberLit() else lexer.readIdent(&keywords),
    };
}

fn check(self: Self, kind: Token.Kind) bool {
    return self.current.kind == kind;
}

fn match(self: *Self, kind: Token.Kind) bool {
    if (self.check(kind)) {
        self.advance();
        return true;
    }

    return false;
}

fn expect(self: *Self, kind: Token.Kind) Error!void {
    if (self.match(kind)) {
        return;
    }

    std.debug.print(
        "Expected {s}, found {s} (\"{s}\") on line {}, in column {}\n",
        .{
            @tagName(kind),
            @tagName(self.current.kind),
            self.current.value,
            self.current.line,
            self.current.column,
        },
    );

    return Error.UnexpectedToken;
}
