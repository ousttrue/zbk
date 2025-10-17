const std = @import("std");
const xml = @import("xml");
const c_types = @import("c_types.zig");

allocator: std.mem.Allocator,

pub fn deinit(this: *@This()) void {
    _ = this;
}

pub fn load(this: *@This(), root: *const xml.Element) (error{
    root_not_registry,
    types_not_found,
} || c_types.Error)!void {
    _ = this;
    if (!std.mem.eql(u8, "registry", root.tag)) {
        return error.root_not_registry;
    }

    const types = root.findChildByTag("types") orelse {
        return error.types_not_found;
    };

    var buf: [1024]u8 = undefined;
    var w = std.fs.File.stderr().writer(&buf);
    errdefer w.interface.flush() catch @panic("OOM");

    var it = types.findChildrenByTag("type");
    var i: u32 = 0;
    while (it.next()) |child| : (i += 1) {
        if (try c_types.parse(child, &w.interface)) |t| {
            std.log.debug("[{}]{f}", .{ i, t });
        }
    }
}
