const std = @import("std");
const Reader = @import("Reader.zig");
const Document = @import("Document.zig");

allocator: std.mem.Allocator,
reader: Reader,

pub fn init(allocator: std.mem.Allocator, source: []const u8) @This() {
    return @This(){
        .allocator = allocator,
        .reader = .{ .source = source },
    };
}
