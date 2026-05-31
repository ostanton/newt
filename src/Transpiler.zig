/// Transpiler to C++
const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;
const ast = @import("ast.zig");

const Error = Writer.Error;

const Self = @This();

pub fn emitLiteral(writer: *Writer, literal: ast.Literal) Error!void {
    switch (literal) {
        .ident => |i| try writer.writeAll(i),
        .string => |s| try writer.print("\"{s}\"", .{s}),
        .int => |i| try writer.print("{}", .{i}),
        .float => |f| try writer.print("{}", .{f}),
        .array => |a| for (a) |expr| try emitExpression(writer, expr),
    }
}

pub fn emitUnary(writer: *Writer, unary: ast.UnaryExpr) Error!void {
    switch (unary.op) {
        .add => try writer.writeByte('+'),
        .minus => try writer.writeByte('-'),
        .not => try writer.writeByte('!'),
    }
    try emitExpression(writer, unary.right);
}

pub fn emitBinary(writer: *Writer, binary: ast.BinaryExpr) Error!void {
    try emitExpression(writer, binary.left);
    switch (binary.op) {
        .assign => try writer.writeAll(" = "),
        .add => try writer.writeAll(" + "),
        .add_assign => try writer.writeAll(" += "),
        .minus => try writer.writeAll(" - "),
        .minus_assign => try writer.writeAll(" -= "),
        .multiply => try writer.writeAll(" * "),
        .multiply_assign => try writer.writeAll(" *= "),
        .divide => try writer.writeAll(" / "),
        .divide_assign => try writer.writeAll(" /= "),
        .equal => try writer.writeAll(" == "),
        .less_than => try writer.writeAll(" < "),
        .greater_than => try writer.writeAll(" > "),
        .less_or_equal => try writer.writeAll(" <= "),
        .greater_or_equal => try writer.writeAll(" >= "),
        .not_equal => try writer.writeAll(" != "),
        .@"or" => try writer.writeAll(" || "),
        .@"and" => try writer.writeAll(" && "),
    }
    try emitExpression(writer, binary.right);
}

pub fn emitFuncCall(writer: *Writer, func_call: ast.FuncCall) Error!void {
    try emitExpression(writer, func_call.left);
    try writer.writeByte('(');
    if (func_call.values) |values| {
        for (values, 0..) |value, i| {
            try emitExpression(writer, value);
            if (i + 1 < values.len) {
                try writer.writeAll(", ");
            }
        }
    }
    try writer.writeByte(')');
}

pub fn emitArrayAccess(writer: *Writer, array_access: ast.ArrayAccess) Error!void {
    try emitExpression(writer, array_access.left);
    try writer.writeByte('[');
    try emitExpression(writer, array_access.value);
    try writer.writeByte(']');
}

pub fn emitMemberAccess(writer: *Writer, member_access: ast.MemberAccess) Error!void {
    try emitExpression(writer, member_access.left);
    // TODO - type check first, so we know if this is a pointer!
    try writer.writeByte('.');
    try writer.writeAll(member_access.member);
}

pub fn emitExpression(writer: *Writer, expr: ast.Expression) Error!void {
    switch (expr) {
        .literal => |l| try emitLiteral(writer, l),
        .unary => |u| try emitUnary(writer, u.*),
        .binary => |b| try emitBinary(writer, b.*),
        .func_call => |f| try emitFuncCall(writer, f.*),
        .array_access => |a| try emitArrayAccess(writer, a.*),
        .member_access => |m| try emitMemberAccess(writer, m.*),
        .layout => |l| _ = l,
    }
}

pub fn emitType(writer: *Writer, in_type: ast.Type) Error!void {
    switch (in_type) {
        .ident => |i| try writer.writeAll(i),
        .array => try writer.writeAll("ARRAY_TODO"),
        .map => try writer.writeAll("MAP_TODO"),
        .pointer => |p| {
            try emitType(writer, p.*);
            try writer.writeByte('*');
        },
    }
}

pub fn emitVarDecl(writer: *Writer, var_decl: ast.VarDecl) Error!void {
    if (var_decl.type) |t| {
        try emitType(writer, t);
    } else {
        try writer.writeAll("auto");
    }

    if (var_decl.constant) {
        try writer.writeAll(" const");
    }

    try writer.print(" {s} = ", .{var_decl.ident});
    if (var_decl.value) |value| {
        try emitExpression(writer, value);
    } else {
        try writer.writeAll("{}");
    }

    try writer.writeByte(';');
}

pub fn emitFuncDecl(writer: *Writer, func_decl: ast.FuncDecl) Error!void {
    // TODO - this needs to know whether it's declared in a function or not
    // to know if it's a lambda
    if (func_decl.return_type) |ret| {
        try emitType(writer, ret);
    } else {
        try writer.writeAll("void");
    }

    try writer.print(" {s}(", .{func_decl.ident});
    if (func_decl.params) |params| {
        for (params, 0..) |param, i| {
            try emitType(writer, param.type);
            try writer.print(" {s}", .{param.ident});
            if (i + 1 < params.len) {
                try writer.writeAll(", ");
            }
        }
    }
    try writer.writeAll(") {");

    if (func_decl.body) |body| {
        try writer.writeByte('\n');
        for (body) |stmt| {
            try emitStatement(writer, stmt);
        }
    }
    try writer.writeByte('}');
}

pub fn emitClassDecl(writer: *Writer, class: ast.ClassDecl) Error!void {
    try writer.print("class {s} {{", .{class.ident});
    if (class.decls) |decls| {
        try writer.writeByte('\n');
        for (decls) |decl| {
            try emitDeclaration(writer, decl);
            try writer.writeByte('\n');
        }
    }
    try writer.writeAll("};");
}

pub fn emitDeclaration(writer: *Writer, decl: ast.Declaration) Error!void {
    switch (decl) {
        .var_decl => |v| try emitVarDecl(writer, v),
        .func_decl => |f| try emitFuncDecl(writer, f),
        .class_decl => |c| try emitClassDecl(writer, c),
    }
}

pub fn emitReturn(writer: *Writer, expr: ast.Expression) Error!void {
    try writer.writeAll("return ");
    try emitExpression(writer, expr);
}

pub fn emitStatement(writer: *Writer, stmt: ast.Statement) Error!void {
    switch (stmt) {
        .decl => |d| try emitDeclaration(writer, d),
        .@"return" => |r| {
            try emitReturn(writer, r);
            try writer.writeByte(';');
        },
        .expr => |e| {
            try emitExpression(writer, e);
            try writer.writeByte(';');
        },
        .@"if" => |i| _ = i,
        .block => |b| {
            try writer.writeAll("{\n");
            for (b) |stmt2| {
                try emitStatement(writer, stmt2);
            }
            try writer.writeByte('}');
        },
    }
    try writer.writeByte('\n');
}
