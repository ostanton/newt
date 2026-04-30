const std = @import("std");

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

        pub const Array = union(enum) {
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
