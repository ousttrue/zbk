const std = @import("std");
const xml = @import("xml");

pub const Error = error{
    not_impl,
    no_name,
    no_type,
};

pub const Define = struct {
    element: *const xml.Element,
    name: []const u8,

    pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} = {f}", .{ this.name, this.element.* });
    }
};

pub const BaseType = struct {
    element: *const xml.Element,
    name: []const u8,
    basetype: []const u8,

    pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} = {s}", .{ this.name, this.basetype });
    }
};

pub const CType = union(enum) {
    define: Define,
    basetype: BaseType,

    pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (this) {
            .define => |define| try writer.print("{f}", .{define}),
            .basetype => |basetype| try writer.print("{f}", .{basetype}),
        }
    }
};

pub fn parse(element: *const xml.Element, debug_writer: *std.Io.Writer) Error!?CType {
    if (element.getAttribute("category")) |category| {
        if (std.mem.eql(u8, "include", category)) {
            return null;
        } else if (std.mem.eql(u8, "define", category)) {
            if (element.findChildByTag("name")) |name| {
                return CType{
                    .define = .{
                        .element = element,
                        .name = name.getCharData(),
                    },
                };
            } else {
                return error.no_name;
            }
        } else if (std.mem.eql(u8, "basetype", category)) {
            if (element.findChildByTag("name")) |name| {
                if (element.findChildByTag("type")) |basetype| {
                    return CType{
                        .basetype = .{
                            .element = element,
                            .name = name.getCharData(),
                            .basetype = basetype.getCharData(),
                        },
                    };
                } else {
                    return error.no_type;
                }
            } else {
                return error.no_name;
            }
        } else if (std.mem.eql(u8, "bitmask", category)) {
            return null;
        } else if (std.mem.eql(u8, "handle", category)) {
            return null;
        } else if (std.mem.eql(u8, "enum", category)) {
            return null;
        } else if (std.mem.eql(u8, "struct", category)) {
            return null;
        } else if (std.mem.eql(u8, "funcpointer", category)) {
            return null;
        } else {
            std.log.err("{f}", .{element});
            element.debugPrint(debug_writer, 0) catch @panic("OOM");
            // std.log.err("{f}", .{element});
            return error.not_impl;
        }
    } else {
        return null;
    }
}
