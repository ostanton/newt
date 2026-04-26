const std = @import("std");
const newt = @import("newt");

const SlotIterator = struct {
    next: *const fn (*SlotIterator) ?*SlotBase,
};

const Children = struct {
    iterator: *const fn (*Children) *SlotIterator,
    addSlot: ?*const fn (*Children, *SlotBase) void = null,
};

const NoChildren = struct {
    base: Children,
    it: Iterator,

    pub var instance: NoChildren = .init();

    const Iterator = struct {
        base: SlotIterator,

        pub fn init() Iterator {
            return .{
                .base = .{ .next = &next },
            };
        }

        fn next(it: *SlotIterator) ?*SlotBase {
            _ = it;
            return null;
        }
    };

    pub fn init() NoChildren {
        return .{
            .base = .{ .iterator = &iterator },
            .it = .init(),
        };
    }

    fn iterator(children: *Children) *SlotIterator {
        const self: *NoChildren = @fieldParentPtr("base", children);
        return &self.it.base;
    }
};

fn PanelChildren(comptime T: type) type {
    return struct {
        base: Children,
        slots: std.SinglyLinkedList,
        it: Iterator,

        const Iterator = struct {
            base: SlotIterator,
            slot: ?*T,

            pub fn init(slot: ?*T) Iterator {
                return .{
                    .base = .{ .next = &next },
                    .slot = slot,
                };
            }

            pub fn next(it: *SlotIterator) ?*SlotBase {
                const self: *Iterator = @fieldParentPtr("base", it);
                if (self.slot) |slot| {
                    if (slot.node.next) |node| {
                        const s: *T = @fieldParentPtr("node", node);
                        return &s.base;
                    }
                }
                return null;
            }

            pub fn nextPanelSlot(self: *Iterator) ?*T {
                if (self.slot) |slot| {
                    if (slot.node.next) |node| {
                        const s: *T = @fieldParentPtr("node", node);
                        return s;
                    }
                }
                return null;
            }
        };

        const Self = @This();

        pub fn init() Self {
            return .{
                .base = .{
                    .iterator = &iterator,
                    .addSlot = &addSlot,
                },
                .slots = .{},
                .it = .init(null),
            };
        }

        fn iterator(children: *Children) *SlotIterator {
            const self: *Self = @fieldParentPtr("base", children);
            if (self.it.slot) |slot| {
                slot.node.next = self.slots.first;
            }
            return &self.it.base;
        }

        fn panelIterator(self: *Self) *Iterator {
            if (self.it.slot) |slot| {
                slot.node.next = self.slots.first;
            }
            return &self.it;
        }

        fn addSlot(children: *Children, slot: *SlotBase) void {
            const self: *Self = @fieldParentPtr("base", children);
            const node = &self.slots.first;
            if (node.* == null) {
                const panel_slot: *T = @fieldParentPtr("base", slot);
                node.* = &panel_slot.node;
                return;
            }

            while (node.*) |n| {
                if (n.next) |next| {
                    node.* = next;
                } else {
                    const panel_slot: *T = @fieldParentPtr("base", slot);
                    n.insertAfter(&panel_slot.node);
                    break;
                }
            }
        }
    };
}

const Widget = struct {
    vtable: *const Vtable,

    const Vtable = struct {
        tick: *const fn (*Widget, f32) void,
        paint: *const fn (*const Widget) void,
        getChildren: *const fn (*Widget) *Children,
        addSlot: ?*const fn (*Widget, *SlotBase) void = null,
        debugWrite: *const fn (*Widget, *std.Io.Writer) std.Io.Writer.Error!void,
    };

    const Self = @This();

    pub fn init(vtable: *const Vtable) Widget {
        return .{
            .vtable = vtable,
        };
    }

    pub fn tick(self: *Self, dt: f32) void {
        self.vtable.tick(self, dt);
    }

    pub fn paint(self: *const Self) void {
        self.vtable.paint(self);
    }

    pub fn getChildren(self: *const Self) *Children {
        return self.vtable.getChildren(self);
    }

    pub fn addSlot(self: *Self, slot: *SlotBase) void {
        if (self.vtable.addSlot) |func| {
            func(self, slot);
        }
    }

    pub fn debugWrite(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return self.vtable.debugWrite(self, writer);
    }
};

const SlotBase = struct {
    content: *Widget,
    vtable: *const Vtable,

    const Vtable = struct {
        debugWrite: *const fn (*SlotBase, *std.Io.Writer) std.Io.Writer.Error!void,
    };

    const Self = @This();

    pub fn init(content: *Widget, vtable: *const Vtable) Self {
        return .{
            .content = content,
            .vtable = vtable,
        };
    }

    pub fn debugWrite(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return self.vtable.debugWrite(self, writer);
    }
};

const VAlign = enum {
    top,
    middle,
    bottom,
    fill,
};

const VBox = struct {
    base: Widget,
    children: PanelChildren(Slot),

    const Slot = struct {
        base: SlotBase,
        alignment: VAlign,
        node: std.SinglyLinkedList.Node,

        pub fn init(content: *Widget, alignment: VAlign) Slot {
            return .{
                .base = .init(
                    content,
                    &.{
                        .debugWrite = &Slot.debugWrite,
                    },
                ),
                .alignment = alignment,
                .node = .{},
            };
        }

        fn debugWrite(slot: *SlotBase, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const self: *Slot = @fieldParentPtr("base", slot);
            try writer.writeAll("VBox.Slot\n");
            try writer.print("alignment: {s}\n", .{@tagName(self.alignment)});
            try writer.writeAll("content:\n");
            try slot.content.debugWrite(writer);
        }
    };

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .init(&.{
                .tick = &tick,
                .paint = &paint,
                .getChildren = &getChildren,
                .addSlot = &addSlot,
                .debugWrite = &debugWrite,
            }),
            .children = .init(),
        };
    }

    fn tick(widget: *Widget, dt: f32) void {
        const self: *Self = @fieldParentPtr("base", widget);
        _ = dt;
        _ = self;
    }

    fn paint(widget: *const Widget) void {
        const self: *const Self = @fieldParentPtr("base", widget);
        _ = self;
    }

    fn getChildren(widget: *Widget) *Children {
        const self: *Self = @fieldParentPtr("base", widget);
        return &self.children.base;
    }

    fn addSlot(widget: *Widget, slot: *SlotBase) void {
        const self: *Self = @fieldParentPtr("base", widget);
        if (self.children.base.addSlot) |func| {
            func(&self.children.base, slot);
        }
    }

    pub fn addVboxSlot(self: *Self, slot: *Slot) void {
        self.base.addSlot(&slot.base);
    }

    fn debugWrite(widget: *Widget, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Self = @fieldParentPtr("base", widget);
        try writer.writeAll("VBox:\n");
        var i: usize = 0;
        var slot_node = self.children.slots.first;
        while (slot_node) |node| : ({
            slot_node = node.next;
            i += 1;
        }) {
            const slot: *Slot = @fieldParentPtr("node", node);
            try writer.print("slot[{}]:\n", .{i});
            try slot.base.debugWrite(writer);
        }
    }
};

const Image = struct {
    base: Widget,

    const Self = @This();

    pub fn init() Self {
        return .{
            .base = .init(&.{
                .tick = &tick,
                .paint = &paint,
                .getChildren = &getChildren,
                .debugWrite = &debugWrite,
            }),
        };
    }

    fn tick(widget: *Widget, dt: f32) void {
        _ = widget;
        _ = dt;
    }

    fn paint(widget: *const Widget) void {
        _ = widget;
    }

    fn getChildren(_: *Widget) *Children {
        return &NoChildren.instance.base;
    }

    fn debugWrite(_: *Widget, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("Image\n");
    }
};

const CreateWidgetFn = fn (std.mem.Allocator) anyerror!*Widget;
const CreateSlotFn = fn (std.mem.Allocator, *Widget) anyerror!*SlotBase;

const widget_map: std.StaticStringMap(*const CreateWidgetFn) = .initComptime(.{
    .{ "Image", &createImage },
    .{ "VBox", &createVbox },
});
const slot_map: std.StaticStringMap(*const CreateSlotFn) = .initComptime(.{
    .{ "VBox", &createVboxSlot },
});

fn createVbox(allocator: std.mem.Allocator) !*Widget {
    const vbox = try allocator.create(VBox);
    vbox.* = .init();
    return &vbox.base;
}

fn createVboxSlot(allocator: std.mem.Allocator, content: *Widget) !*SlotBase {
    const slot = try allocator.create(VBox.Slot);
    slot.* = .init(content, .fill);
    return &slot.base;
}

fn createImage(allocator: std.mem.Allocator) !*Widget {
    const image = try allocator.create(Image);
    image.* = .init();
    return &image.base;
}

const PropertyRegistry = struct {
    map: std.StringHashMapUnmanaged(*Property),
};

const PropertyBase = struct {
    owner: *Widget,

    const Self = @This();

    pub fn value(self: Self, comptime T: type) T {
        const PropType: type = comptime switch (@typeInfo(T)) {
            .bool => BoolProperty,
            .int => IntProperty,
            .float => FloatProperty,
            .array => |array| switch (@typeInfo(array.child)) {
                .int => |int| if (int.bits == 8) StringProperty,
                else => ArrayProperty,
            },
            else => @compileError("Invalid property type"),
        };

        const child: *const PropType = @fieldParentPtr("base", &self);
        return child.value;
    }
};

fn Property(comptime T: type) type {
    return struct {
        base: PropertyBase,
        value: T,

        const Self = @This();

        pub fn init(owner: *Widget, value: T) Self {
            return .{
                .base = .{
                    .owner = owner,
                },
                .value = value,
            };
        }
    };
}

const BoolProperty = Property(bool);
const IntProperty = Property(i32);
const FloatProperty = Property(f32);
const StringProperty = Property([]const u8);
const IdentProperty = Property([]const u8);
const ArrayProperty = Property([]*PropertyBase);

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
        }
    }

    // var vbox: VBox = .init();
    // var image1: Image = .init();
    // var img_slot1: VBox.Slot = .init(&image1.base, .fill);
    // var image2: Image = .init();
    // var img_slot2: VBox.Slot = .init(&image2.base, .middle);
    // vbox.addVboxSlot(&img_slot1);
    // vbox.addVboxSlot(&img_slot2);

    // var vbox2: VBox = .init();
    // var vbox_slot2: VBox.Slot = .init(&vbox2.base, .fill);
    // var image3: Image = .init();
    // var img_slot3: VBox.Slot = .init(&image3.base, .bottom);
    // vbox.addVboxSlot(&vbox_slot2);
    // vbox2.addVboxSlot(&img_slot3);

    // var buffer: [1024]u8 = undefined;
    // var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    // try vbox.base.debugWrite(&writer.interface);
    // try writer.interface.flush();
}

fn parseLayout(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    std.debug.print("Layout path: {s}\n", .{path});
    const root = try newt.layout.parseFile(
        allocator,
        io,
        try std.Io.Dir.cwd().openFile(io, path, .{}),
    );
    defer root.deinit(allocator);

    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    try newt.layout.ast.writeWidget(&writer.interface, root);
    try writer.flush();

    // no deinit!!
    const root_widget = try createWidgetFromLayoutWidget(allocator, root);
    if (root_widget) |widget| {
        try widget.debugWrite(&writer.interface);
        try writer.flush();
    } else {
        std.log.err("Failed to create widget tree!", .{});
    }
}

fn createWidgetFromLayoutWidget(allocator: std.mem.Allocator, widget: newt.layout.ast.Widget) !?*Widget {
    if (widget_map.get(widget.name)) |create_widget_func| {
        const ptr = try create_widget_func(allocator);
        if (widget.slots) |slots| {
            for (slots) |slot| {
                if (slot_map.get(widget.name)) |create_slot_func| {
                    const content_widget = try createWidgetFromLayoutWidget(allocator, slot.widget);
                    if (content_widget) |content| {
                        ptr.addSlot(try create_slot_func(allocator, content));
                    }
                }
            }
        }
        return ptr;
    }

    return null;
}
