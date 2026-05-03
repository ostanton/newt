const std = @import("std");
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");
const ast = @import("ast.zig");

lexer: Lexer,
current: Token,

const Self = @This();

pub const Error = error{
    UnexpectedToken,
    InvalidSyntax,
} || std.Io.Reader.LimitedAllocError || std.mem.Allocator.Error;

const Mode = enum {
    script,
    layout,
};

pub fn init(src: []const u8, mode: Mode) Self {
    var self: Self = .{
        .lexer = .{
            .src = src,
            .pos = 0,
            .line = 1,
            .column = 1,
        },
        .current = undefined,
    };
    self.advance(mode);
    return self;
}

pub fn parseStatement(self: *Self, allocator: std.mem.Allocator) Error!ast.Statement {
    switch (self.current.kind) {
        .ident => {
            const ident = self.current.value;
            const peek_token = self.peek(.script);
            switch (peek_token.kind) {
                .colon => {
                    self.advance(.script);
                    const decl = try self.parseDeclaration(allocator, ident);
                    switch (decl) {
                        .var_decl => |v| return .{ .var_decl = v },
                        else => {
                            std.log.err(
                                "Illegal declaration in scope at line {} in column {}",
                                .{
                                    self.current.line, self.current.column,
                                },
                            );
                            return Error.InvalidSyntax;
                        },
                    }
                },
                else => {},
            }
        },
        .@"if" => return .{ .@"if" = try self.parseIfStatement(allocator) },
        .@"return" => {
            self.advance(.script);
            const expr = try self.parseExpression(allocator, 0, .script);
            if (self.check(.semicolon)) {
                self.advance(.script);
            }
            return .{ .@"return" = expr };
        },
        else => {},
    }

    // TODO - semicolons are entirely optional at the moment, even for multiple statements on a single line.
    // Might want to enforce semicolons for that case, like Go?
    const expr = try self.parseExpression(allocator, 0, .script);
    if (self.check(.semicolon)) {
        self.advance(.script);
    }
    return .{ .expr = expr };
}

pub fn parseDeclaration(self: *Self, allocator: std.mem.Allocator, ident: []const u8) Error!ast.Declaration {
    try self.expect(.colon, .script);

    var typename: ?[]const u8 = null;
    if (self.check(.ident)) {
        typename = self.current.value;
        self.advance(.script);
    }

    const constant = if (self.check(.colon)) true else if (self.check(.equal)) false else {
        // Assume zero-initialised variable
        if (self.check(.semicolon)) {
            self.advance(.script);
        }
        return .{
            .var_decl = .{
                .ident = ident,
                .type = typename,
                .value = null,
                .constant = false,
            },
        };
    };

    self.advance(.script);

    switch (self.current.kind) {
        .func => {
            if (!constant) {
                std.log.err(
                    "Function '{s}' on line {} in column {} must be constant",
                    .{
                        ident,
                        self.current.line,
                        self.current.column,
                    },
                );
                return Error.InvalidSyntax;
            }

            return .{ .func_decl = try self.parseFuncDecl(allocator, ident) };
        },
        .class => {
            if (!constant) {
                std.log.err(
                    "Class '{s}' on line {} in column {} must be constant",
                    .{
                        ident,
                        self.current.line,
                        self.current.column,
                    },
                );
                return Error.InvalidSyntax;
            }

            return .{ .class_decl = try self.parseClassDecl(allocator, ident) };
        },
        .@"enum" => std.log.warn("TODO - parse enum", .{}),
        else => {},
    }

    // Assume variable declaration
    const value = try self.parseExpression(allocator, 0, .script);
    if (self.check(.semicolon)) {
        self.advance(.script);
    }
    return .{
        .var_decl = .{
            .ident = ident,
            .type = typename,
            .value = value,
            .constant = constant,
        },
    };
}

pub fn parseFuncDecl(self: *Self, allocator: std.mem.Allocator, ident: []const u8) Error!ast.FuncDecl {
    try self.expect(.func, .script);
    try self.expect(.left_bracket, .script);
    var params: std.ArrayList(ast.FuncDecl.Param) = .empty;
    errdefer params.deinit(allocator);
    while (!self.check(.right_bracket)) {
        try params.append(allocator, try self.parseFuncParam());
    }
    try self.expect(.right_bracket, .script);

    var return_type: ?[]const u8 = null;
    if (self.check(.ident)) {
        return_type = self.current.value;
        self.advance(.script);
    }

    try self.expect(.left_brace, .script);
    var body: std.ArrayList(ast.Statement) = .empty;
    errdefer {
        for (body.items) |stmt| {
            stmt.deinit(allocator);
        }
        body.deinit(allocator);
    }
    while (!self.check(.right_brace)) {
        try body.append(allocator, try self.parseStatement(allocator));
    }
    try self.expect(.right_brace, .script);

    return .{
        .ident = ident,
        .params = if (params.items.len > 0) try params.toOwnedSlice(allocator) else null,
        .return_type = return_type,
        .body = if (body.items.len > 0) try body.toOwnedSlice(allocator) else null,
    };
}

pub fn parseFuncParam(self: *Self) Error!ast.FuncDecl.Param {
    if (!self.check(.ident)) {
        return Error.UnexpectedToken;
    }

    const ident = self.current.value;
    self.advance(.script);

    try self.expect(.colon, .script);

    if (!self.check(.ident)) {
        return Error.UnexpectedToken;
    }
    const typename = self.current.value;
    self.advance(.script);

    return .{
        .ident = ident,
        .type = typename,
    };
}

pub fn parseClassDecl(self: *Self, allocator: std.mem.Allocator, ident: []const u8) Error!ast.ClassDecl {
    try self.expect(.class, .script);
    try self.expect(.left_brace, .script);
    const body = try self.parseClassBody(allocator, ident);
    errdefer body.deinit(allocator);
    try self.expect(.right_brace, .script);

    return body;
}

pub fn parseClassBody(self: *Self, allocator: std.mem.Allocator, ident: []const u8) Error!ast.ClassDecl {
    var decls: std.ArrayList(ast.Declaration) = .empty;
    errdefer {
        for (decls.items) |decl| {
            decl.deinit(allocator);
        }
        decls.deinit(allocator);
    }
    while (!self.check(.right_brace) and !self.check(.eof)) {
        if (!self.check(.ident)) {
            std.log.err(
                "Expected indentifier for declaration in class {s}, found {s} (\"{s}\") on line {} in column {}",
                .{
                    ident,
                    @tagName(self.current.kind),
                    self.current.value,
                    self.current.line,
                    self.current.column,
                },
            );
            return Error.UnexpectedToken;
        }

        const decl_ident = self.current.value;
        self.advance(.script);
        try decls.append(allocator, try self.parseDeclaration(allocator, decl_ident));
    }
    return .{
        .ident = ident,
        .decls = if (decls.items.len > 0) try decls.toOwnedSlice(allocator) else null,
    };
}

pub fn parseIfStatement(self: *Self, allocator: std.mem.Allocator) Error!ast.If {
    try self.expect(.@"if", .script);

    const cond = try self.parseExpression(allocator, 0, .script);
    errdefer cond.deinit(allocator);

    try self.expect(.left_brace, .script);
    var then_body: std.ArrayList(ast.Statement) = .empty;
    errdefer {
        for (then_body.items) |stmt| {
            stmt.deinit(allocator);
        }
        then_body.deinit(allocator);
    }
    while (!self.check(.right_brace)) {
        try then_body.append(allocator, try self.parseStatement(allocator));
    }
    try self.expect(.right_brace, .script);

    var elifs: std.ArrayList(ast.If.Elif) = .empty;
    errdefer {
        for (elifs.items) |elif| {
            elif.deinit(allocator);
        }
        elifs.deinit(allocator);
    }

    var else_body: std.ArrayList(ast.Statement) = .empty;
    errdefer {
        for (else_body.items) |stmt| {
            stmt.deinit(allocator);
        }
        else_body.deinit(allocator);
    }

    while (self.match(.@"else", .script)) {
        if (self.match(.@"if", .script)) {
            const elif_cond = try self.parseExpression(allocator, 0, .script);
            errdefer elif_cond.deinit(allocator);

            try self.expect(.left_brace, .script);
            var elif_body: std.ArrayList(ast.Statement) = .empty;
            errdefer {
                for (elif_body.items) |stmt| {
                    stmt.deinit(allocator);
                }
                elif_body.deinit(allocator);
            }
            while (!self.check(.right_brace)) {
                try elif_body.append(allocator, try self.parseStatement(allocator));
            }
            try self.expect(.right_brace, .script);

            try elifs.append(
                allocator,
                .{
                    .cond = elif_cond,
                    .body = if (elif_body.items.len > 0) try elif_body.toOwnedSlice(allocator) else null,
                },
            );
        } else {
            try self.expect(.left_brace, .script);
            while (!self.check(.right_brace)) {
                try else_body.append(allocator, try self.parseStatement(allocator));
            }
            try self.expect(.right_brace, .script);
            break;
        }
    }

    return .{
        .cond = cond,
        .then_body = if (then_body.items.len > 0) try then_body.toOwnedSlice(allocator) else null,
        .elifs = if (elifs.items.len > 0) try elifs.toOwnedSlice(allocator) else null,
        .else_body = if (else_body.items.len > 0) try else_body.toOwnedSlice(allocator) else null,
    };
}

pub fn parseWidget(self: *Self, allocator: std.mem.Allocator) Error!ast.Widget {
    if (!self.check(.ident)) {
        std.log.err(
            "Expected widget identifier, found {s} on line {} in column {}",
            .{
                @tagName(self.current.kind),
                self.current.line,
                self.current.column,
            },
        );
        return Error.UnexpectedToken;
    }

    const name = self.current.value;
    self.advance(.layout);

    var props_arr: std.ArrayList(ast.Property) = .empty;
    errdefer {
        for (props_arr.items) |prop| {
            prop.deinit(allocator);
        }
        props_arr.deinit(allocator);
    }
    while (self.check(.ident)) {
        try props_arr.append(allocator, try self.parseProperty(allocator));
        if (!self.match(.comma, .layout)) {
            break;
        }
    }

    var slots_arr: std.ArrayList(ast.Slot) = .empty;
    errdefer {
        for (slots_arr.items) |slot| {
            slot.deinit(allocator);
        }
        slots_arr.deinit(allocator);
    }
    while (self.match(.plus, .layout)) {
        try slots_arr.append(allocator, try self.parseSlot(allocator));
    }

    return .{
        .name = name,
        .props = if (props_arr.items.len > 0) try props_arr.toOwnedSlice(allocator) else null,
        .slots = if (slots_arr.items.len > 0) try slots_arr.toOwnedSlice(allocator) else null,
    };
}

pub fn parseSlot(self: *Self, allocator: std.mem.Allocator) Error!ast.Slot {
    var props_arr: std.ArrayList(ast.Property) = .empty;
    errdefer {
        for (props_arr.items) |prop| {
            prop.deinit(allocator);
        }
        props_arr.deinit(allocator);
    }
    while (self.check(.ident)) {
        try props_arr.append(allocator, try self.parseProperty(allocator));
        if (!self.match(.comma, .layout)) {
            break;
        }
    }

    try self.expect(.left_bracket, .layout);
    var widget = try self.parseWidget(allocator);
    errdefer widget.deinit(allocator);
    try self.expect(.right_bracket, .layout);

    return .{
        .props = if (props_arr.items.len > 0) try props_arr.toOwnedSlice(allocator) else null,
        .widget = widget,
    };
}

pub fn parseProperty(self: *Self, allocator: std.mem.Allocator) Error!ast.Property {
    if (!self.check(.ident)) {
        std.log.err(
            "Expected property identifier, found {s} on line {} in column {}",
            .{
                @tagName(self.current.kind),
                self.current.line,
                self.current.column,
            },
        );
        return Error.UnexpectedToken;
    }

    const key = self.current.value;
    self.advance(.layout);

    if (!(self.match(.equal, .layout) or self.match(.equal_greater_than, .layout))) {
        std.log.err(
            "Expected equal or binding operator on line {} in column {}",
            .{
                self.current.line,
                self.current.column,
            },
        );
        return Error.UnexpectedToken;
    }

    return .{
        .key = key,
        .value = try self.parsePropertyValue(allocator),
    };
}

pub fn parsePropertyValue(self: *Self, allocator: std.mem.Allocator) Error!ast.Property.Value {
    if (self.match(.dollar, .layout)) {
        try self.expect(.left_bracket, .layout);
        const expr = try self.parseExpression(allocator, 0, .script);
        errdefer expr.deinit(allocator);
        try self.expect(.right_bracket, .layout);
        return .{ .expr = expr };
    }

    const token = self.current;
    self.advance(.layout);
    return switch (token.kind) {
        .ident => .{ .literal = .{ .ident = token.value } },
        .string_lit => .{ .literal = .{ .string = token.value } },
        .number_lit => .{ .literal = .{ .number = token.value } },
        .left_bracket => .{ .tuple = try self.parsePropertyValueContainer(allocator, .right_bracket) },
        .left_square => .{ .array = try self.parsePropertyValueContainer(allocator, .right_square) },
        else => blk: {
            std.log.err(
                "Expected a literal property value, found {s} (\"{s}\") on line {} in column {}",
                .{
                    @tagName(token.kind),
                    token.value,
                    token.line,
                    token.column,
                },
            );
            break :blk Error.UnexpectedToken;
        },
    };
}

pub fn parsePropertyValueContainer(self: *Self, allocator: std.mem.Allocator, term_kind: Token.Kind) Error![]ast.Property.Value {
    var values: std.ArrayList(ast.Property.Value) = .empty;
    errdefer values.deinit(allocator);

    while (!self.check(term_kind)) {
        try values.append(allocator, try self.parsePropertyValue(allocator));
        if (!self.match(.comma, .layout)) {
            break;
        }
    }

    try self.expect(term_kind, .layout);
    return try values.toOwnedSlice(allocator);
}

pub fn parseExpression(self: *Self, allocator: std.mem.Allocator, min_prec: u8, mode: Mode) Error!ast.Expression {
    var left = try self.parsePrimary(allocator, mode);
    errdefer left.deinit(allocator);

    while (true) {
        const node = try self.parseIncreasingPrecedence(
            allocator,
            left,
            min_prec,
            mode,
        );
        if (left.eql(node)) {
            break;
        }

        left = node;
    }

    return left;
}

fn parseIncreasingPrecedence(
    self: *Self,
    allocator: std.mem.Allocator,
    left: ast.Expression,
    min_prec: u8,
    mode: Mode,
) Error!ast.Expression {
    const next = self.current;

    const postfix_prec: u8 = 50;

    if (next.kind == .left_bracket) {
        if (postfix_prec <= min_prec) {
            return left;
        }

        self.advance(.script);
        const func_call = try allocator.create(ast.FuncCall);
        errdefer allocator.destroy(func_call);

        var values: std.ArrayList(ast.Expression) = .empty;
        errdefer {
            for (values.items) |value| {
                value.deinit(allocator);
            }
            values.deinit(allocator);
        }
        while (!self.check(.right_bracket)) {
            try values.append(allocator, try self.parseExpression(allocator, 0, .script));
            if (!self.match(.comma, .script)) {
                break;
            }
        }
        try self.expect(.right_bracket, .script);

        func_call.* = .{
            .left = left,
            .values = if (values.items.len > 0) try values.toOwnedSlice(allocator) else null,
        };
        return .{ .func_call = func_call };
    }

    if (next.kind == .left_square) {
        if (postfix_prec <= min_prec) {
            return left;
        }

        self.advance(.script);
        const array_access = try allocator.create(ast.ArrayAccess);
        errdefer allocator.destroy(array_access);

        const value = try self.parseExpression(allocator, 0, .script);
        errdefer value.deinit(allocator);

        try self.expect(.right_square, .script);
        array_access.* = .{
            .left = left,
            .value = value,
        };
        return .{ .array_access = array_access };
    }

    if (next.kind == .dot) {
        if (postfix_prec <= min_prec) {
            return left;
        }

        self.advance(.script);
        if (!self.check(.ident)) {
            std.log.err(
                "Expected identifier after dot, found {s} on line {} in column {}",
                .{
                    @tagName(self.current.kind),
                    self.current.line,
                    self.current.column,
                },
            );
            return Error.UnexpectedToken;
        }

        const member = self.current.value;
        const member_access = try allocator.create(ast.MemberAccess);
        member_access.* = .{
            .left = left,
            .member = member,
        };
        self.advance(.script);
        return .{ .member_access = member_access };
    }

    const op = ast.BinaryExpr.Operator.initFromTokenKind(next.kind) orelse return left;
    const next_prec = op.getPrecedence();
    if (next_prec <= min_prec) {
        return left;
    }

    self.advance(mode);
    const right = try self.parseExpression(allocator, next_prec, mode);
    errdefer right.deinit(allocator);
    const binary = try allocator.create(ast.BinaryExpr);
    binary.* = .{
        .left = left,
        .op = op,
        .right = right,
    };
    return .{ .binary = binary };
}

fn parsePrimary(self: *Self, allocator: std.mem.Allocator, mode: Mode) Error!ast.Expression {
    const token = self.current;
    const operator = ast.UnaryExpr.Operator.initFromTokenKind(token.kind);
    if (operator) |op| {
        self.advance(mode);
        const right = try self.parsePrimary(allocator, mode);
        errdefer right.deinit(allocator);
        const unary = try allocator.create(ast.UnaryExpr);
        unary.* = .{
            .op = op,
            .right = right,
        };
        return .{ .unary = unary };
    }

    self.advance(mode);
    switch (token.kind) {
        .ident => return .{ .literal = .{ .ident = token.value } },
        .string_lit => return .{ .literal = .{ .string = token.value } },
        .number_lit => return .{ .literal = .{ .number = token.value } },
        .layout => {
            try self.expect(.left_brace, .script);
            const layout = try self.parseWidget(allocator);
            try self.expect(.right_brace, .script);
            return .{ .layout = layout };
        },
        else => {},
    }

    std.log.err(
        "Unexpected token {s} (\"{s}\") parsing primary on line {} in column {}",
        .{
            @tagName(token.kind),
            token.value,
            token.line,
            token.column,
        },
    );
    return Error.UnexpectedToken;
}

fn advance(self: *Self, mode: Mode) void {
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
    self.current = switch (mode) {
        .script => lexer.lexScript(char),
        .layout => lexer.lexLayout(char),
    };
}

fn peek(self: *Self, mode: Mode) Token {
    if (self.lexer.peek()) |char| {
        const pos = self.lexer.pos;
        const line = self.lexer.line;
        const column = self.lexer.line;

        const token = switch (mode) {
            .layout => self.lexer.lexLayout(char),
            .script => self.lexer.lexScript(char),
        };

        self.lexer.pos = pos;
        self.lexer.line = line;
        self.lexer.column = column;
        return token;
    }

    return .{
        .kind = .eof,
        .value = "",
        .line = self.lexer.line,
        .column = self.lexer.column,
    };
}

fn check(self: Self, kind: Token.Kind) bool {
    return self.current.kind == kind;
}

fn match(self: *Self, kind: Token.Kind, mode: Mode) bool {
    if (self.check(kind)) {
        self.advance(mode);
        return true;
    }

    return false;
}

fn expect(self: *Self, kind: Token.Kind, mode: Mode) Error!void {
    if (self.match(kind, mode)) {
        return;
    }

    std.log.err(
        "Expected {s}, found {s} (\"{s}\") in mode {s} on line {} in column {}",
        .{
            @tagName(kind),
            @tagName(self.current.kind),
            self.current.value,
            @tagName(mode),
            self.current.line,
            self.current.column,
        },
    );
    return Error.UnexpectedToken;
}
