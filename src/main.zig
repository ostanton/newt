const std = @import("std");
const newt = @import("newt");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    // const gpa = init.gpa;

    var vm: newt.VirtualMachine = .init(&.{
        .{ .push_i32 = 14 },
        .{ .push_i32 = 10 },
        .{ .div_i32 = {} },
        .{ .print_i32 = {} },
        .{ .push_f32 = 1216.5 },
        .{ .push_f32 = 342.1 },
        .{ .div_f32 = {} },
        .{ .print_f32 = {} },
    });
    while (vm.ip < vm.code.len) : (vm.ip += 1) {
        const instr = vm.code[vm.ip];
        try vm.execute(instr);
    }

    var args = try init.minimal.args.iterateAllocator(arena);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print(
                \\newt standalone compiler.
                \\Usage: newt [arg value]
                \\
                \\Arguments:
                \\  -l, --layout [path]    Parses and pretty prints a layout file
                \\  -s, --script [path]    Compiles a script file into bytecode for the newt VM
                \\  -h, --help             Prints this help screen
            , .{});
            return;
        } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--layout")) {
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
        } else {
            std.log.warn("Invalid argument. Use -h or --help for help.", .{});
            return;
        }
    }
}

fn parseLayout(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
        std.log.err("Failed to open layout '{s}'", .{path});
        return;
    };
    defer file.close(io);
    var read_buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const src = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(src);

    std.log.info("Parsing layout '{s}'", .{path});
    var root = newt.layout.parseString(allocator, src) catch |err| {
        std.log.err("Failed to parse layout: {}", .{err});
        return;
    };
    defer root.deinit(allocator);
    std.log.info("Finished parsing layout", .{});

    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    try newt.ast.writeWidget(&writer.interface, root);
    try writer.flush();
}

fn parseScript(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
        std.log.err("Failed to open script '{s}'", .{path});
        return;
    };
    defer file.close(io);
    var read_buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const src = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(src);

    std.log.info("Parsing script '{s}'", .{path});
    const class_name = std.Io.Dir.path.stem(path);
    var ast = newt.script.parseString(allocator, src, class_name) catch |err| {
        std.log.err("Failed to parse script: {}", .{err});
        return;
    };
    defer ast.deinit(allocator);
    std.log.info("Finished parsing script", .{});

    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    try newt.ast.writeAst(&writer.interface, ast);
    try writer.flush();
}
