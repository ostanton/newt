const std = @import("std");
const newt = @import("newt");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    // const gpa = init.gpa;

    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--layout")) {
            if (args.next()) |path| {
                try parseLayout(arena, io, path);
            } else {
                std.log.err("No layout file specified", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--script")) {
            if (args.next()) |path| {
                try parseScript(arena, io, path);
            } else {
                std.log.err("No script file specified", .{});
                return;
            }
        }
    }
}

fn parseLayout(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
        std.log.err("Failed to open layout '{s}'", .{path});
        return;
    };
    defer file.close(io);
    std.log.info("Parsing layout '{s}'", .{path});
    var root = try newt.layout.parseFile(
        allocator,
        io,
        file,
    );
    defer root.deinit(allocator);

    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    try newt.layout.ast.writeWidget(&writer.interface, root);
    try writer.flush();
}

fn parseScript(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
        std.log.err("Failed to open script '{s}'", .{path});
        return;
    };
    defer file.close(io);
    std.log.info("Parsing script '{s}'", .{path});
    _ = allocator;
}
