/// Base lexer functionality for both the layout DSL and scripting language
const std = @import("std");
const Token = @import("Token.zig");

src: []const u8,
pos: usize,
line: usize,
column: usize,

const Self = @This();

pub fn peek(self: Self) ?u8 {
    if (self.pos + 1 >= self.src.len) {
        return null;
    }

    return self.src[self.pos];
}

pub fn makeToken(self: *Self, kind: Token.Kind, value: []const u8) Token {
    return self.makeTokenEx(kind, value, 1, 1);
}

pub fn makeTokenEx(self: *Self, kind: Token.Kind, value: []const u8, pos_offset: usize, col_offset: usize) Token {
    self.pos += pos_offset;
    self.column += col_offset;
    return .{
        .kind = kind,
        .value = value,
        .line = self.line,
        .column = self.column,
    };
}

pub fn skipWhitespace(self: *Self) void {
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

pub fn readStringLit(self: *Self) Token {
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

pub fn readNumberLit(self: *Self) Token {
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

pub fn readIdent(self: *Self, keywords: *const std.StaticStringMap(Token.Kind)) Token {
    const start = self.pos;
    const start_col = self.column;

    while (self.pos < self.src.len and (std.ascii.isAlphanumeric(self.src[self.pos]) or self.src[self.pos] == '_')) {
        self.pos += 1;
        self.column += 1;
    }

    const value = self.src[start..self.pos];
    var kind: Token.Kind = .ident;
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
