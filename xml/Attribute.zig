const std = @import("std");
const Reader = @import("Reader.zig");

name: []const u8,
value: []const u8,

pub fn parse(allocator: std.mem.Allocator, reader: *Reader) !?@This() {
    const name = reader.parseName() catch return null;
    _ = reader.eatWs();
    try reader.expect('=');
    _ = reader.eatWs();
    const value = try reader.allocParseAttrValue(allocator);

    const attr = @This(){
        .name = try allocator.dupe(u8, name.slice),
        .value = value,
    };
    return attr;
}

pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(this.name);
    allocator.free(this.value);
}
