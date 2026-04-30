/// Layout DSL parsing
const std = @import("std");

pub const TokenKind = enum {
    ident,
    /// 32-bit signed
    int_lit,
    /// 32-bit
    float_lit,
    string_lit,
    true_lit,
    false_lit,
    plus,
    assign,
    binding,
    multi_binding,
    left_bracket,
    right_bracket,
    left_square,
    right_square,
    comma,
    eof,
};

pub const Token = struct {
    kind: TokenKind,
    value: []const u8,
    line: usize,
    column: usize,
};

pub const Lexer = struct {
    src: []const u8,
    pos: usize,
    line: usize,
    column: usize,

    const Self = @This();
    const keywords: std.StaticStringMap(TokenKind) = .initComptime(.{
        .{ "true", .true_lit },
        .{ "false", .false_lit },
    });

    pub fn advance(self: *Self) Token {
        self.skipWhitespace();

        if (self.pos >= self.src.len) {
            return .{
                .kind = .eof,
                .value = "",
                .line = self.line,
                .column = self.column,
            };
        }

        const char = self.src[self.pos];
        switch (char) {
            '+' => return self.makeToken(.plus, "+"),
            '(' => return self.makeToken(.left_bracket, "("),
            ')' => return self.makeToken(.right_bracket, ")"),
            '[' => return self.makeToken(.left_square, "["),
            ']' => return self.makeToken(.right_square, "]"),
            ',' => return self.makeToken(.comma, ","),
            '=' => if (self.peek()) |c| switch (c) {
                '>' => return self.makeTokenEx(.binding, "=>", 2, 2),
                else => return self.makeToken(.assign, "="),
            },
            '"' => {
                self.pos += 1;
                self.column += 1;
                return self.readStringLit();
            },
            else => {},
        }

        if (std.ascii.isDigit(char) or char == '-') {
            return self.readNumberLit();
        } else {
            return self.readIdent();
        }
    }

    pub fn peek(self: Self) ?u8 {
        if (self.pos + 1 >= self.src.len) {
            return null;
        }

        return self.src[self.pos + 1];
    }

    fn makeToken(self: *Self, kind: TokenKind, value: []const u8) Token {
        return self.makeTokenEx(kind, value, 1, 1);
    }

    fn makeTokenEx(self: *Self, kind: TokenKind, value: []const u8, pos_offset: usize, col_offset: usize) Token {
        self.pos += pos_offset;
        self.column += col_offset;
        return .{
            .kind = kind,
            .value = value,
            .line = self.line,
            .column = self.column,
        };
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.src.len) {
            const char = self.src[self.pos];

            if (std.ascii.isWhitespace(char)) {
                // Normal whitespace
                if (char == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }

                self.pos += 1;
            } else if (char == '#' and self.pos + 1 < self.src.len) {
                // # comment, ignore until new line
                self.pos += 1;
                self.column += 1;

                while (self.pos < self.src.len and self.src[self.pos] != '\n') {
                    self.pos += 1;
                    self.column += 1;
                }
            } else {
                // Not whitespace or comment, we've reached valid code
                break;
            }
        }
    }

    fn readStringLit(self: *Self) Token {
        const start = self.pos;
        const start_col = self.column;

        while (self.pos < self.src.len) : ({
            self.pos += 1;
            self.column += 1;
        }) {
            const char = self.src[self.pos];
            if (char == '"') {
                const end = self.pos;
                self.pos += 1;
                self.column += 1;
                return .{
                    .kind = .string_lit,
                    .value = self.src[start..end],
                    .line = self.line,
                    .column = start_col,
                };
            }

            if (char == '\n') {
                break;
            }
        }

        // Error in string
        return .{
            .kind = .eof,
            .value = self.src[start - 1 .. self.pos],
            .line = self.line,
            .column = start_col,
        };
    }

    fn readNumberLit(self: *Self) Token {
        const start = self.pos;
        const start_col = self.column;

        if (self.src[self.pos] == '-') {
            self.pos += 1;
            self.column += 1;
        }

        while (self.pos < self.src.len and std.ascii.isDigit(self.src[self.pos])) {
            self.pos += 1;
            self.column += 1;
        }

        // Not a digit, check for floating point
        if (self.pos < self.src.len and self.src[self.pos] == '.') {
            self.pos += 1;
            self.column += 1;

            // Consume other side of point
            while (self.pos < self.src.len and std.ascii.isDigit(self.src[self.pos])) {
                self.pos += 1;
                self.column += 1;
            }

            return .{
                .kind = .float_lit,
                .value = self.src[start..self.pos],
                .line = self.line,
                .column = start_col,
            };
        }

        return .{
            .kind = .int_lit,
            .value = self.src[start..self.pos],
            .line = self.line,
            .column = start_col,
        };
    }

    fn readIdent(self: *Self) Token {
        const start = self.pos;
        const start_col = self.column;

        while (self.pos < self.src.len and (std.ascii.isAlphanumeric(self.src[self.pos]) or self.src[self.pos] == '_')) {
            self.pos += 1;
            self.column += 1;
        }

        const value = self.src[start..self.pos];
        var kind: TokenKind = .ident;
        if (keywords.get(value)) |k| {
            kind = k;
        }

        return .{
            .kind = kind,
            .value = value,
            .line = self.line,
            .column = start_col,
        };
    }
};

pub const ast = struct {
    pub const Property = struct {
        key: []u8,
        value: Value,

        pub const Value = union(enum) {
            bool: bool,
            float: f32,
            int: i32,
            string: []u8,
            ident: []u8,
            array: Array,
            tuple: std.ArrayList(Value),

            const Array = union(enum) {
                bool: std.ArrayList(bool),
                float: std.ArrayList(f32),
                int: std.ArrayList(i32),
                string: std.ArrayList([]u8),

                pub fn deinit(self: *Array, allocator: std.mem.Allocator) void {
                    switch (self.*) {
                        .bool => |*b| b.deinit(allocator),
                        .float => |*f| f.deinit(allocator),
                        .int => |*i| i.deinit(allocator),
                        .string => |*s| {
                            for (s.items) |string| {
                                allocator.free(string);
                            }
                            s.deinit(allocator);
                        },
                    }
                }
            };

            pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .string, .ident => |s| allocator.free(s),
                    .array => |*a| a.deinit(allocator),
                    .tuple => |*t| {
                        for (t.items) |*value| {
                            value.deinit(allocator);
                        }
                        t.deinit(allocator);
                    },
                    else => {},
                }
            }
        };

        pub fn deinit(self: *Property, allocator: std.mem.Allocator) void {
            allocator.free(self.key);
            self.value.deinit(allocator);
        }
    };

    pub const Widget = struct {
        name: []u8,
        properties: std.ArrayList(Property),
        slots: std.ArrayList(Slot),

        pub fn deinit(self: *Widget, allocator: std.mem.Allocator) void {
            allocator.free(self.name);

            for (self.properties.items) |*prop| {
                prop.deinit(allocator);
            }
            self.properties.deinit(allocator);

            for (self.slots.items) |*slot| {
                slot.deinit(allocator);
            }
            self.slots.deinit(allocator);
        }
    };

    pub const Slot = struct {
        properties: std.ArrayList(Property),
        widget: Widget,

        pub fn deinit(self: *Slot, allocator: std.mem.Allocator) void {
            for (self.properties.items) |*prop| {
                prop.deinit(allocator);
            }
            self.properties.deinit(allocator);

            self.widget.deinit(allocator);
        }
    };

    pub fn writeWidget(writer: *std.Io.Writer, widget: Widget) !void {
        var ast_writer: Writer = .{
            .writer = writer,
            .indent_level = 0,
            .indent_amount = 4,
        };
        try ast_writer.writeWidget(widget);
    }

    const Writer = struct {
        writer: *std.Io.Writer,
        indent_level: usize,
        indent_amount: usize,

        fn writeIndent(self: Writer) std.Io.Writer.Error!void {
            for (0..self.indent_level * self.indent_amount) |_| {
                try self.writer.writeByte(' ');
            }
        }

        fn writeWidget(self: *Writer, widget: Widget) std.Io.Writer.Error!void {
            try self.writer.print("{s}", .{widget.name});

            for (widget.properties.items) |prop| {
                try self.writer.writeByte(' ');
                try self.writeProperty(prop);
            }

            if (widget.slots.items.len > 0) {
                try self.writer.writeByte('\n');
                for (widget.slots.items) |slot| {
                    try self.writeSlot(slot);
                }
            }
        }

        fn writeProperty(self: *Writer, prop: Property) std.Io.Writer.Error!void {
            try self.writer.print("{s}=", .{prop.key});
            try self.writePropertyValue(prop.value);
        }

        fn writePropertyValue(self: *Writer, value: Property.Value) std.Io.Writer.Error!void {
            switch (value) {
                .bool => |b| try self.writer.print("{}", .{b}),
                .float => |f| try self.writer.print("{}", .{f}),
                .int => |i| try self.writer.print("{}", .{i}),
                .string => |s| try self.writer.print("\"{s}\"", .{s}),
                .ident => |i| try self.writer.writeAll(i),
                .array => |a| {
                    try self.writer.writeByte('[');
                    switch (a) {
                        .bool => |b| {
                            for (b.items, 0..) |v, i| {
                                try self.writer.print("{}", .{v});
                                if (i + 1 < b.items.len) {
                                    try self.writer.writeAll(", ");
                                }
                            }
                        },
                        .float => |f| {
                            for (f.items, 0..) |v, i| {
                                try self.writer.print("{}", .{v});
                                if (i + 1 < f.items.len) {
                                    try self.writer.writeAll(", ");
                                }
                            }
                        },
                        .int => |i| {
                            for (i.items, 0..) |v, j| {
                                try self.writer.print("{}", .{v});
                                if (j + 1 < i.items.len) {
                                    try self.writer.writeAll(", ");
                                }
                            }
                        },
                        .string => |s| {
                            for (s.items, 0..) |v, i| {
                                try self.writer.print("\"{s}\"", .{v});
                                if (i + 1 < s.items.len) {
                                    try self.writer.writeAll(", ");
                                }
                            }
                        },
                    }
                    try self.writer.writeByte(']');
                },
                .tuple => |t| {
                    try self.writer.writeByte('(');
                    for (t.items, 0..) |v, i| {
                        try self.writePropertyValue(v);
                        if (i + 1 < t.items.len) {
                            try self.writer.writeAll(", ");
                        }
                    }
                    try self.writer.writeByte(')');
                },
            }
        }

        fn writeSlot(self: *Writer, slot: Slot) std.Io.Writer.Error!void {
            try self.writeIndent();
            try self.writer.writeAll("+ ");

            for (slot.properties.items) |prop| {
                try self.writeProperty(prop);
                try self.writer.writeByte(' ');
            }

            self.indent_level += 1;
            try self.writer.writeByte('(');
            try self.writeWidget(slot.widget);
            try self.writer.writeAll(")\n");
            self.indent_level -= 1;
        }
    };
};

pub const ParseError = error{
    UnexpectedToken,
    InvalidSyntax,

    InvalidCharacter,
    Overflow,
} || std.Io.Reader.LimitedAllocError;

pub fn parseFile(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File) ParseError!ast.Widget {
    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    return parseReader(allocator, &file_reader.interface);
}

pub fn parseReader(allocator: std.mem.Allocator, reader: *std.Io.Reader) ParseError!ast.Widget {
    const src = try reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(src);
    return parseString(allocator, src);
}

pub fn parseString(allocator: std.mem.Allocator, src: []const u8) ParseError!ast.Widget {
    var parser: Parser = .init(allocator, src);
    return parser.parseWidget();
}

pub const Parser = struct {
    lexer: Lexer,
    current: Token,
    allocator: std.mem.Allocator,

    const Self = @This();

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
        self.current = self.lexer.advance();
        return self;
    }

    fn parseWidget(self: *Self) ParseError!ast.Widget {
        if (!self.check(.ident)) {
            return ParseError.UnexpectedToken;
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

    fn parseSlot(self: *Self) ParseError!ast.Slot {
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

    fn parseProperty(self: *Self) ParseError!ast.Property {
        if (!self.check(.ident)) {
            return ParseError.UnexpectedToken;
        }

        const key = try self.allocator.dupe(u8, self.current.value);
        errdefer self.allocator.free(key);
        self.advance();

        if (!(self.match(.assign) or self.match(.binding))) {
            // TODO - error, requires assignment of some kind
            return ParseError.UnexpectedToken;
        }

        return .{
            .key = key,
            .value = try self.parsePropertyValue(),
        };
    }

    fn parsePropertyValue(self: *Self) ParseError!ast.Property.Value {
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
            else => return ParseError.UnexpectedToken,
        };
        self.advance();
        return value;
    }

    fn parsePropertyValueArray(self: *Self) ParseError!ast.Property.Value.Array {
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
            else => return ParseError.UnexpectedToken,
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
                    else => return ParseError.InvalidSyntax,
                },
                .false_lit => switch (dyn_arr) {
                    .bool => |*b| try b.append(self.allocator, false),
                    else => return ParseError.InvalidSyntax,
                },
                .float_lit => switch (dyn_arr) {
                    .float => |*f| try f.append(self.allocator, try std.fmt.parseFloat(f32, self.current.value)),
                    else => return ParseError.InvalidSyntax,
                },
                .int_lit => switch (dyn_arr) {
                    .int => |*i| try i.append(self.allocator, try std.fmt.parseInt(i32, self.current.value, 10)),
                    else => return ParseError.InvalidSyntax,
                },
                .string_lit => switch (dyn_arr) {
                    .string => |*s| try s.append(self.allocator, try self.allocator.dupe(u8, self.current.value)),
                    else => return ParseError.InvalidSyntax,
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
        self.current = self.lexer.advance();
    }

    fn check(self: Self, kind: TokenKind) bool {
        return self.current.kind == kind;
    }

    fn match(self: *Self, kind: TokenKind) bool {
        if (self.check(kind)) {
            self.advance();
            return true;
        }

        return false;
    }

    fn expect(self: *Self, kind: TokenKind) ParseError!void {
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

        return ParseError.UnexpectedToken;
    }
};
