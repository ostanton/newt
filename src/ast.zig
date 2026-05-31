const std = @import("std");
const Token = @import("Token.zig");

pub const Literal = union(enum) {
    ident: []const u8,
    string: []const u8,
    /// i32 can probably be coerced to f32, but not vice versa
    int: i32,
    float: f32,
    /// Check if these are all the same type later or something
    array: []Expression,

    pub fn eql(self: Literal, other: Literal) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) {
            return false;
        }

        return switch (self) {
            .ident => |i| std.mem.eql(u8, i, other.ident),
            .string => |s| std.mem.eql(u8, s, other.string),
            .int => |i| i == other.int,
            .float => |f| f == other.float,
            .array => |a| {
                if (a.len != other.array.len) {
                    return false;
                }

                for (a, other.array) |arr, arr2| {
                    if (!arr.eql(arr2)) {
                        return false;
                    }
                }

                return true;
            },
        };
    }
};

pub const Type = union(enum) {
    ident: []const u8,
    array: *Type,
    map: *Map,
    pointer: *Type,

    pub const Map = struct {
        key: Type,
        value: Type,
    };

    pub fn deinit(self: Type, allocator: std.mem.Allocator) void {
        switch (self) {
            .array, .pointer => |t| {
                t.deinit(allocator);
                allocator.destroy(t);
            },
            .map => |m| {
                m.key.deinit(allocator);
                m.value.deinit(allocator);
                allocator.destroy(m);
            },
            else => {},
        }
    }
};

pub const UnaryExpr = struct {
    op: Operator,
    right: Expression,

    pub const Operator = enum {
        add,
        minus,
        not,

        pub fn initFromTokenKind(kind: Token.Kind) ?Operator {
            return switch (kind) {
                .plus => .add,
                .minus => .minus,
                .bang => .not,
                else => null,
            };
        }
    };

    pub fn eql(self: UnaryExpr, other: UnaryExpr) bool {
        return self.op == other.op and self.right.eql(other.right);
    }

    pub fn deinit(self: UnaryExpr, allocator: std.mem.Allocator) void {
        self.right.deinit(allocator);
    }
};

pub const BinaryExpr = struct {
    left: Expression,
    op: Operator,
    right: Expression,

    pub const Operator = enum {
        assign,
        add,
        add_assign,
        minus,
        minus_assign,
        multiply,
        multiply_assign,
        divide,
        divide_assign,
        equal,
        less_than,
        greater_than,
        less_or_equal,
        greater_or_equal,
        not_equal,
        @"or",
        @"and",

        pub fn initFromTokenKind(kind: Token.Kind) ?Operator {
            return switch (kind) {
                .equal => .assign,
                .plus => .add,
                .plus_equal => .add_assign,
                .minus => .minus,
                .minus_equal => .minus_assign,
                .star => .multiply,
                .star_equal => .multiply_assign,
                .slash => .divide,
                .slash_equal => .divide_assign,
                .equal_equal => .equal,
                .less_than => .less_than,
                .greater_than => .greater_than,
                .less_than_equal => .less_or_equal,
                .greater_than_equal => .greater_or_equal,
                .bang_equal => .not_equal,
                .@"or" => .@"or",
                .@"and" => .@"and",
                else => null,
            };
        }

        pub fn getPrecedence(self: Operator) u8 {
            return switch (self) {
                .assign,
                .add_assign,
                .minus_assign,
                .multiply_assign,
                .divide_assign,
                => 1,
                .@"or" => 2,
                .@"and" => 3,
                .equal, .not_equal => 4,
                .less_than, .greater_than, .less_or_equal, .greater_or_equal => 5,
                .add, .minus => 6,
                .multiply, .divide => 7,
            };
        }
    };

    pub fn eql(self: BinaryExpr, other: BinaryExpr) bool {
        return self.left.eql(other.left) and self.op == other.op and self.right.eql(other.right);
    }

    pub fn deinit(self: BinaryExpr, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.right.deinit(allocator);
    }
};

pub const FuncCall = struct {
    left: Expression,
    values: ?[]Expression,

    pub fn eql(self: FuncCall, other: FuncCall) bool {
        if (!self.left.eql(other.left)) {
            return false;
        }

        if (self.values) |values| {
            if (other.values) |values2| {
                if (values.len != values2.len) {
                    return false;
                }

                for (values, values2) |v, v2| {
                    if (!v.eql(v2)) {
                        return false;
                    }
                }
            } else {
                return false;
            }
        } else if (other.values != null) {
            return false;
        }

        return true;
    }

    pub fn deinit(self: FuncCall, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        if (self.values) |values| {
            for (values) |value| {
                value.deinit(allocator);
            }
            allocator.free(values);
        }
    }
};

pub const ArrayAccess = struct {
    left: Expression,
    value: Expression,

    pub fn eql(self: ArrayAccess, other: ArrayAccess) bool {
        return self.left.eql(other.left) and self.value.eql(other.value);
    }

    pub fn deinit(self: ArrayAccess, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.value.deinit(allocator);
    }
};

pub const MemberAccess = struct {
    left: Expression,
    member: []const u8,

    pub fn eql(self: MemberAccess, other: MemberAccess) bool {
        return self.left.eql(other.left) and std.mem.eql(u8, self.member, other.member);
    }

    pub fn deinit(self: MemberAccess, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
    }
};

pub const Expression = union(enum) {
    literal: Literal,
    unary: *UnaryExpr,
    binary: *BinaryExpr,
    func_call: *FuncCall,
    array_access: *ArrayAccess,
    member_access: *MemberAccess,
    layout: Widget,

    pub fn eql(self: Expression, other: Expression) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) {
            return false;
        }

        return switch (self) {
            .literal => |l| l.eql(other.literal),
            .unary => |u| u.eql(other.unary.*),
            .binary => |b| b.eql(other.binary.*),
            .func_call => |f| f.eql(other.func_call.*),
            .array_access => |a| a.eql(other.array_access.*),
            .member_access => |m| m.eql(other.member_access.*),
            .layout => |l| l.eql(other.layout),
        };
    }

    pub fn deinit(self: Expression, allocator: std.mem.Allocator) void {
        switch (self) {
            .unary => |u| {
                u.deinit(allocator);
                allocator.destroy(u);
            },
            .binary => |b| {
                b.deinit(allocator);
                allocator.destroy(b);
            },
            .func_call => |f| f.deinit(allocator),
            .array_access => |a| {
                a.deinit(allocator);
                allocator.destroy(a);
            },
            .member_access => |m| {
                m.deinit(allocator);
                allocator.destroy(m);
            },
            .layout => |l| l.deinit(allocator),
            else => {},
        }
    }
};

pub const VarDecl = struct {
    ident: []const u8,
    type: ?Type,
    value: ?Expression,
    constant: bool,

    pub fn deinit(self: VarDecl, allocator: std.mem.Allocator) void {
        if (self.type) |t| {
            t.deinit(allocator);
        }

        if (self.value) |value| {
            value.deinit(allocator);
        }
    }
};

pub const FuncDecl = struct {
    ident: []const u8,
    params: ?[]Param,
    return_type: ?Type,
    body: ?[]Statement,

    pub const Param = struct {
        ident: []const u8,
        type: Type,
    };

    pub fn deinit(self: FuncDecl, allocator: std.mem.Allocator) void {
        if (self.params) |params| {
            for (params) |param| {
                param.type.deinit(allocator);
            }
            allocator.free(params);
        }

        if (self.return_type) |t| {
            t.deinit(allocator);
        }

        if (self.body) |body| {
            for (body) |stmt| {
                stmt.deinit(allocator);
            }
            allocator.free(body);
        }
    }
};

pub const ClassDecl = struct {
    ident: []const u8,
    decls: ?[]Declaration,

    pub fn deinit(self: ClassDecl, allocator: std.mem.Allocator) void {
        if (self.decls) |decls| {
            for (decls) |d| {
                d.deinit(allocator);
            }
            allocator.free(decls);
        }
    }
};

pub const Declaration = union(enum) {
    var_decl: VarDecl,
    func_decl: FuncDecl,
    class_decl: ClassDecl,

    pub fn getIdent(self: Declaration) []const u8 {
        return switch (self) {
            .var_decl => |v| v.ident,
            .func_decl => |f| f.ident,
            .class_decl => |c| c.ident,
        };
    }

    pub fn deinit(self: Declaration, allocator: std.mem.Allocator) void {
        switch (self) {
            .var_decl => |v| v.deinit(allocator),
            .func_decl => |f| f.deinit(allocator),
            .class_decl => |c| c.deinit(allocator),
        }
    }
};

pub const If = struct {
    cond: Expression,
    then_body: ?[]Statement,
    elifs: ?[]Elif,
    else_body: ?[]Statement,

    pub const Elif = struct {
        cond: Expression,
        body: ?[]Statement,

        pub fn deinit(self: Elif, allocator: std.mem.Allocator) void {
            self.cond.deinit(allocator);
            if (self.body) |body| {
                for (body) |stmt| {
                    stmt.deinit(allocator);
                }
                allocator.free(body);
            }
        }
    };

    pub fn deinit(self: If, allocator: std.mem.Allocator) void {
        self.cond.deinit(allocator);
        if (self.then_body) |then| {
            for (then) |stmt| {
                stmt.deinit(allocator);
            }
            allocator.free(then);
        }
        if (self.elifs) |elifs| {
            for (elifs) |elif| {
                elif.deinit(allocator);
            }
            allocator.free(elifs);
        }
        if (self.else_body) |body| {
            for (body) |stmt| {
                stmt.deinit(allocator);
            }
            allocator.free(body);
        }
    }
};

pub const Statement = union(enum) {
    expr: Expression,
    decl: Declaration,
    @"if": If,
    @"return": Expression,
    block: []Statement,

    pub fn deinit(self: Statement, allocator: std.mem.Allocator) void {
        switch (self) {
            .expr => |e| e.deinit(allocator),
            .decl => |d| d.deinit(allocator),
            .@"if" => |i| i.deinit(allocator),
            .@"return" => |r| r.deinit(allocator),
            .block => |b| {
                for (b) |stmt| {
                    stmt.deinit(allocator);
                }
                allocator.free(b);
            },
        }
    }
};

pub const Property = struct {
    key: []const u8,
    value: Value,

    pub const Value = union(enum) {
        literal: Literal,
        array: []Value,
        tuple: []Value,
        /// A script expression, wrapped in $()
        expr: Expression,

        pub fn eql(self: Value, other: Value) bool {
            if (@intFromEnum(self) != @intFromEnum(other)) {
                return false;
            }

            return switch (self) {
                .literal => |l| l.eql(other.literal),
                .array => |a| blk: {
                    if (a.len != other.array.len) {
                        break :blk false;
                    }

                    for (a, other.array) |arr, arr2| {
                        if (!arr.eql(arr2)) {
                            break :blk false;
                        }
                    }

                    break :blk true;
                },
                .tuple => |t| blk: {
                    if (t.len != other.tuple.len) {
                        break :blk false;
                    }

                    for (t, other.tuple) |arr, arr2| {
                        if (!arr.eql(arr2)) {
                            break :blk false;
                        }
                    }

                    break :blk true;
                },
                .expr => |e| e.eql(other.expr),
            };
        }
    };

    pub fn eql(self: Property, other: Property) bool {
        return std.mem.eql(u8, self.key, other.key) and self.value.eql(other.value);
    }

    pub fn deinit(self: Property, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .expr => |e| e.deinit(allocator),
            else => {},
        }
    }
};

pub const Widget = struct {
    name: []const u8,
    props: ?[]Property,
    slots: ?[]Slot,

    pub fn eql(self: Widget, other: Widget) bool {
        if (!std.mem.eql(u8, self.name, other.name)) {
            return false;
        }

        if (self.props) |props| {
            if (other.props) |props2| {
                if (props.len != props2.len) {
                    return false;
                }

                for (props, props2) |p, p2| {
                    if (!p.eql(p2)) {
                        return false;
                    }
                }
            } else {
                return false;
            }
        } else if (other.props != null) {
            return false;
        }

        if (self.slots) |slots| {
            if (other.slots) |slots2| {
                if (slots.len != slots2.len) {
                    return false;
                }

                for (slots, slots2) |s, s2| {
                    if (!s.eql(s2)) {
                        return false;
                    }
                }
            } else {
                return false;
            }
        } else if (other.slots != null) {
            return false;
        }

        return true;
    }

    pub fn deinit(self: Widget, allocator: std.mem.Allocator) void {
        if (self.props) |props| {
            for (props) |prop| {
                prop.deinit(allocator);
            }
            allocator.free(props);
        }
        if (self.slots) |slots| {
            for (slots) |slot| {
                slot.deinit(allocator);
            }
            allocator.free(slots);
        }
    }
};

pub const Slot = struct {
    props: ?[]Property,
    widget: Widget,

    pub fn eql(self: Slot, other: Slot) bool {
        if (!self.widget.eql(other.widget)) {
            return false;
        }

        if (self.props) |props| {
            if (other.props) |props2| {
                if (props.len != props2.len) {
                    return false;
                }

                for (props, props2) |p, p2| {
                    if (!p.eql(p2)) {
                        return false;
                    }
                }
            } else {
                return false;
            }
        } else if (other.props != null) {
            return false;
        }

        return true;
    }

    pub fn deinit(self: Slot, allocator: std.mem.Allocator) void {
        if (self.props) |props| {
            for (props) |prop| {
                prop.deinit(allocator);
            }
            allocator.free(props);
        }
        self.widget.deinit(allocator);
    }
};

pub fn writeAst(writer: *std.Io.Writer, ast: ClassDecl) !void {
    var ast_writer: Writer = .{
        .writer = writer,
        .indent_level = 0,
        .indent_amount = 2,
    };
    try ast_writer.writeClassDecl(ast);
}

pub fn writeWidget(writer: *std.Io.Writer, widget: Widget) !void {
    var ast_writer: Writer = .{
        .writer = writer,
        .indent_level = 0,
        .indent_amount = 2,
    };
    try ast_writer.writeWidget(widget);
}

pub const Writer = struct {
    writer: *std.Io.Writer,
    indent_level: usize,
    indent_amount: usize,

    const Error = std.Io.Writer.Error;

    fn writeIndent(self: Writer) std.Io.Writer.Error!void {
        for (0..self.indent_level * self.indent_amount) |_| {
            try self.writer.writeByte(' ');
        }
    }

    pub fn writeLiteral(self: *Writer, literal: Literal) Error!void {
        switch (literal) {
            .ident => |i| try self.writer.writeAll(i),
            .string => |s| try self.writer.print("\"{s}\"", .{s}),
            .int => |i| try self.writer.print("{}", .{i}),
            .float => |f| try self.writer.print("{}", .{f}),
            .array => |a| {
                try self.writer.writeByte('[');
                for (a, 0..) |expr, i| {
                    try self.writeExpression(expr);
                    if (i + 1 < a.len) {
                        try self.writer.writeAll(", ");
                    }
                }
                try self.writer.writeByte(']');
            },
        }
    }

    pub fn writeUnary(self: *Writer, unary: UnaryExpr) Error!void {
        switch (unary.op) {
            .add => try self.writer.writeByte('+'),
            .minus => try self.writer.writeByte('-'),
            .not => try self.writer.writeByte('!'),
        }
        try self.writeExpression(unary.right);
    }

    pub fn writeBinary(self: *Writer, binary: BinaryExpr) Error!void {
        try self.writeExpression(binary.left);
        switch (binary.op) {
            .assign => try self.writer.writeAll(" = "),
            .add => try self.writer.writeAll(" + "),
            .add_assign => try self.writer.writeAll(" += "),
            .minus => try self.writer.writeAll(" - "),
            .minus_assign => try self.writer.writeAll(" -= "),
            .multiply => try self.writer.writeAll(" * "),
            .multiply_assign => try self.writer.writeAll(" *= "),
            .divide => try self.writer.writeAll(" / "),
            .divide_assign => try self.writer.writeAll(" /= "),
            .equal => try self.writer.writeAll(" == "),
            .less_than => try self.writer.writeAll(" < "),
            .greater_than => try self.writer.writeAll(" > "),
            .less_or_equal => try self.writer.writeAll(" <= "),
            .greater_or_equal => try self.writer.writeAll(" >= "),
            .not_equal => try self.writer.writeAll(" != "),
            .@"or" => try self.writer.writeAll(" or "),
            .@"and" => try self.writer.writeAll(" and "),
        }
        try self.writeExpression(binary.right);
    }

    pub fn writeFuncCall(self: *Writer, func_call: FuncCall) Error!void {
        try self.writeExpression(func_call.left);
        try self.writer.writeByte('(');
        if (func_call.values) |values| {
            for (values, 0..) |value, i| {
                try self.writeExpression(value);
                if (i + 1 < values.len) {
                    try self.writer.writeAll(", ");
                }
            }
        }
        try self.writer.writeByte(')');
    }

    pub fn writeArrayAccess(self: *Writer, array_access: ArrayAccess) Error!void {
        try self.writeExpression(array_access.left);
        try self.writer.writeByte('[');
        try self.writeExpression(array_access.value);
        try self.writer.writeByte(']');
    }

    pub fn writeMemberAccess(self: *Writer, member_access: MemberAccess) Error!void {
        try self.writeExpression(member_access.left);
        try self.writer.writeByte('.');
        try self.writer.writeAll(member_access.member);
    }

    pub fn writeExpression(self: *Writer, expr: Expression) Error!void {
        switch (expr) {
            .literal => |l| try self.writeLiteral(l),
            .unary => |u| try self.writeUnary(u.*),
            .binary => |b| try self.writeBinary(b.*),
            .func_call => |f| try self.writeFuncCall(f.*),
            .array_access => |a| try self.writeArrayAccess(a.*),
            .member_access => |m| try self.writeMemberAccess(m.*),
            .layout => |l| {
                try self.writer.writeAll("layout {\n");
                self.indent_amount += 1;
                try self.writeIndent();
                try self.writeWidget(l);
                self.indent_amount -= 1;
                try self.writeIndent();
                try self.writer.writeByte('}');
            },
        }
    }

    pub fn writeType(self: *Writer, in_type: Type) Error!void {
        switch (in_type) {
            .ident => |i| try self.writer.writeAll(i),
            .array => |a| {
                try self.writer.writeAll("[]");
                try self.writeType(a.*);
            },
            .map => |m| {
                try self.writer.writeByte('[');
                try self.writeType(m.key);
                try self.writer.writeByte(']');
                try self.writeType(m.value);
            },
            .pointer => |p| {
                try self.writer.writeByte('*');
                try self.writeType(p.*);
            },
        }
    }

    pub fn writeVarDecl(self: *Writer, var_decl: VarDecl) Error!void {
        try self.writer.print(
            "{s} :",
            .{var_decl.ident},
        );
        if (var_decl.type) |typename| {
            try self.writer.writeByte(' ');
            try self.writeType(typename);
            try self.writer.writeByte(' ');
        }
        if (var_decl.value) |value| {
            try self.writer.writeAll(if (var_decl.constant) ": " else "= ");
            try self.writeExpression(value);
        }
    }

    pub fn writeFuncDecl(self: *Writer, func_decl: FuncDecl) Error!void {
        try self.writer.print("{s} :: func(", .{func_decl.ident});
        if (func_decl.params) |params| {
            for (params, 0..) |param, i| {
                try self.writer.print("{s}: ", .{param.ident});
                try self.writeType(param.type);
                if (i + 1 < params.len) {
                    try self.writer.writeAll(", ");
                }
            }
        }
        try self.writer.writeAll(") ");
        if (func_decl.return_type) |ret| {
            try self.writeType(ret);
            try self.writer.writeByte(' ');
        }
        try self.writer.writeByte('{');
        if (func_decl.body) |body| {
            try self.writer.writeByte('\n');
            self.indent_level += 1;
            for (body) |stmt| {
                try self.writeIndent();
                try self.writeStatement(stmt);
            }
            self.indent_level -= 1;
        }
        try self.writeIndent();
        try self.writer.writeByte('}');
    }

    pub fn writeClassDecl(self: *Writer, class_decl: ClassDecl) Error!void {
        try self.writer.print("{s} :: class {{", .{class_decl.ident});
        if (class_decl.decls) |decls| {
            try self.writer.writeByte('\n');
            self.indent_level += 1;
            for (decls) |d| {
                try self.writeIndent();
                try self.writeDeclaration(d);
                try self.writer.writeByte('\n');
            }
            self.indent_level -= 1;
        }
        try self.writeIndent();
        try self.writer.writeByte('}');
    }

    pub fn writeDeclaration(self: *Writer, decl: Declaration) Error!void {
        switch (decl) {
            .var_decl => |v| try self.writeVarDecl(v),
            .func_decl => |f| try self.writeFuncDecl(f),
            .class_decl => |c| try self.writeClassDecl(c),
        }
    }

    pub fn writeReturn(self: *Writer, expr: Expression) Error!void {
        try self.writer.writeAll("return ");
        try self.writeExpression(expr);
    }

    pub fn writeIf(self: *Writer, if_stmt: If) Error!void {
        try self.writer.writeAll("if ");
        try self.writeExpression(if_stmt.cond);
        try self.writer.writeAll(" {");
        if (if_stmt.then_body) |body| {
            try self.writer.writeByte('\n');
            self.indent_level += 1;
            for (body) |stmt| {
                try self.writeIndent();
                try self.writeStatement(stmt);
            }
            self.indent_level -= 1;
        }
        try self.writeIndent();
        try self.writer.writeByte('}');

        if (if_stmt.elifs) |elifs| {
            for (elifs) |elif| {
                try self.writer.writeAll(" else if ");
                try self.writeExpression(elif.cond);
                try self.writer.writeAll(" {");
                if (elif.body) |body| {
                    try self.writer.writeByte('\n');
                    self.indent_level += 1;
                    for (body) |stmt| {
                        try self.writeIndent();
                        try self.writeStatement(stmt);
                    }
                    self.indent_level -= 1;
                }
                try self.writeIndent();
                try self.writer.writeByte('}');
            }
        }

        if (if_stmt.else_body) |body| {
            try self.writer.writeAll(" else {\n");
            self.indent_level += 1;
            for (body) |stmt| {
                try self.writeIndent();
                try self.writeStatement(stmt);
            }
            self.indent_level -= 1;
            try self.writeIndent();
            try self.writer.writeByte('}');
        }
    }

    pub fn writeStatement(self: *Writer, stmt: Statement) Error!void {
        switch (stmt) {
            .decl => |d| try self.writeDeclaration(d),
            .@"return" => |r| try self.writeReturn(r),
            .expr => |e| {
                try self.writeExpression(e);
            },
            .@"if" => |i| try self.writeIf(i),
            .block => |b| {
                try self.writer.writeAll("{\n");
                self.indent_level += 1;
                for (b) |stmt2| {
                    try self.writeIndent();
                    try self.writeStatement(stmt2);
                }
                self.indent_level -= 1;
                try self.writeIndent();
                try self.writer.writeAll("}");
            },
        }
        try self.writer.writeByte('\n');
    }

    pub fn writeWidget(self: *Writer, widget: Widget) Error!void {
        try self.writer.print("{s}", .{widget.name});

        if (widget.props) |props| {
            try self.writer.writeByte(' ');
            for (props, 0..) |prop, i| {
                try self.writeProperty(prop);
                if (i + 1 < props.len) {
                    try self.writer.writeByte(' ');
                }
            }
        }

        if (widget.slots) |slots| {
            try self.writer.writeByte('\n');
            for (slots) |slot| {
                try self.writeSlot(slot);
            }
        }
    }

    pub fn writeProperty(self: *Writer, prop: Property) Error!void {
        try self.writer.print("{s}=", .{prop.key});
        try self.writePropertyValue(prop.value);
    }

    pub fn writePropertyValue(self: *Writer, value: Property.Value) Error!void {
        switch (value) {
            .literal => |l| try self.writeLiteral(l),
            .array => |a| {
                try self.writer.writeByte('[');
                for (a, 0..) |val, i| {
                    try self.writePropertyValue(val);
                    if (i + 1 < a.len) {
                        try self.writer.writeAll(", ");
                    }
                }
                try self.writer.writeByte(']');
            },
            .tuple => |t| {
                try self.writer.writeByte('(');
                for (t, 0..) |val, i| {
                    try self.writePropertyValue(val);
                    if (i + 1 < t.len) {
                        try self.writer.writeAll(", ");
                    }
                }
                try self.writer.writeByte(')');
            },
            .expr => |e| {
                try self.writer.writeAll("$(");
                try self.writeExpression(e);
                try self.writer.writeByte(')');
            },
        }
    }

    pub fn writeSlot(self: *Writer, slot: Slot) Error!void {
        try self.writeIndent();
        try self.writer.writeByte('+');

        if (slot.props) |props| {
            try self.writer.writeByte(' ');
            for (props, 0..) |prop, i| {
                try self.writeProperty(prop);
                if (i + 1 < props.len) {
                    try self.writer.writeByte(' ');
                }
            }
            try self.writer.writeByte(' ');
        }

        self.indent_level += 1;
        try self.writer.writeByte('(');
        try self.writeWidget(slot.widget);
        try self.writer.writeAll(")\n");
        self.indent_level -= 1;
    }
};
