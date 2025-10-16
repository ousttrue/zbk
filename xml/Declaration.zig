const std = @import("std");
const Reader = @import("Reader.zig");
const Attribute = @import("Attribute.zig");

tag: []const u8,
attributes: []Attribute = &.{},
line: usize,
column: usize,

pub fn parse(allocator: std.mem.Allocator, reader: *Reader) !?*@This() {
    const start = reader.offset;

    if (!reader.eatStr("<?")) return null;

    const tag = reader.parseName() catch {
        reader.offset = start;
        return null;
    };

    var attributes = std.array_list.Managed(Attribute).init(allocator);
    defer attributes.deinit();

    while (reader.eatWs()) {
        const attr = (try Attribute.parse(allocator, reader)) orelse break;
        try attributes.append(attr);
    }

    try reader.expectStr("?>");

    const element = try allocator.create(@This());
    element.* = .{
        .tag = try allocator.dupe(u8, tag.slice),
        .attributes = try attributes.toOwnedSlice(),
        .line = tag.line,
        .column = tag.column,
    };
    return element;
}

pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(this.tag);
    for (this.attributes) |*attribute| {
        attribute.deinit(allocator);
    }
    allocator.free(this.attributes);
}

pub fn destroy(this: *@This(), allocator: std.mem.Allocator) void {
    this.deinit(allocator);
    allocator.destroy(this);
}

pub fn getAttribute(this: *@This(), attrib_name: []const u8) ?[]const u8 {
    for (this.attributes) |child| {
        if (std.mem.eql(u8, child.name, attrib_name)) {
            return child.value;
        }
    }

    return null;
}

test "xml: parse prolog" {
    const a = std.testing.allocator;

    {
        var reader = Reader{ .source = "<?xmla version='aa'?>" };
        const decl = try @This().parse(a, &reader) orelse return error.no_decl;
        defer decl.destroy(a);
        try std.testing.expectEqualSlices(u8, decl.tag, "xmla");
        try std.testing.expectEqualSlices(u8, "aa", decl.getAttribute("version").?);
    }

    {
        var reader = Reader{ .source = "<?xml version='aa'?>" };
        const decl = try @This().parse(a, &reader) orelse return error.no_decl;
        defer decl.destroy(a);
        try std.testing.expectEqualSlices(u8, "aa", decl.getAttribute("version").?);
        try std.testing.expectEqual(@as(?[]const u8, null), decl.getAttribute("encoding"));
        try std.testing.expectEqual(@as(?[]const u8, null), decl.getAttribute("standalone"));
    }

    {
        var reader = Reader{ .source = "<?xml version=\"ccc\" encoding = 'bbb' standalone   \t =   'yes'?>" };
        const decl = try @This().parse(a, &reader) orelse return error.no_decl;
        defer decl.destroy(a);
        try std.testing.expectEqualSlices(u8, "ccc", decl.getAttribute("version").?);
        try std.testing.expectEqualSlices(u8, "bbb", decl.getAttribute("encoding").?);
        try std.testing.expectEqualSlices(u8, "yes", decl.getAttribute("standalone").?);
    }
}
