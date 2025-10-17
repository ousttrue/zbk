const std = @import("std");
const Reader = @import("Reader.zig");
const Attribute = @import("Attribute.zig");

const Element = @This();

pub const Content = union(enum) {
    char_data: []const u8,
    comment: []const u8,
    element: *Element,

    pub fn parse(allocator: std.mem.Allocator, reader: *Reader) Reader.ParseError!Content {
        if (try reader.allocParseCharData(allocator)) |cd| {
            return Content{ .char_data = cd };
        } else if (try reader.parseComment()) |comment| {
            return Content{ .comment = try allocator.dupe(u8, comment) };
        } else if (Element.parse(allocator, reader)) |elem| {
            return Content{ .element = elem };
        } else |e| {
            return e;
        }
    }

    pub fn deinit(this: *Content, allocator: std.mem.Allocator) void {
        switch (this.*) {
            .char_data => |char_data| {
                allocator.free(char_data);
            },
            .comment => |comment| {
                allocator.free(comment);
            },
            .element => |element| {
                element.deinit(allocator);
                allocator.destroy(element);
            },
        }
    }

    pub fn dumpString(this: *const @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (this.*) {
            .char_data => |char_data| {
                try w.print(" {s}", .{std.mem.trim(
                    u8,
                    char_data,
                    &std.ascii.whitespace,
                )});
            },
            .comment => {},
            .element => |element| {
                if (std.mem.eql(u8, "name", element.tag)) {
                    if (element.children.len == 1) {
                        try element.children[0].dumpString(w);
                    } else {
                        return error.WriteFailed;
                    }
                } else {
                    // return error.WriteFailed;
                }
            },
        }
    }
};

tag: []const u8,
attributes: []Attribute = &.{},
children: []Content = &.{},
line: usize,
column: usize,

pub fn parse(allocator: std.mem.Allocator, reader: *Reader) Reader.ParseError!*@This() {
    const start = reader.offset;

    if (!reader.eat('<')) return error.NonMatchingOpeningTag;

    const tag = reader.parseName() catch {
        reader.offset = start;
        return error.NonMatchingOpeningTag;
    };

    var attributes = std.array_list.Managed(Attribute).init(allocator);
    defer attributes.deinit();

    var children = std.array_list.Managed(Content).init(allocator);
    defer children.deinit();

    while (reader.eatWs()) {
        const attr = (try Attribute.parse(allocator, reader)) orelse break;
        try attributes.append(attr);
    }

    if (!reader.eatStr("/>")) {
        try reader.expect('>');

        while (true) {
            if (reader.peek() == null) {
                return error.UnexpectedEof;
            } else if (reader.eatStr("</")) {
                break;
            }

            const content = try Content.parse(allocator, reader);
            try children.append(content);
        }

        const closing_tag = try reader.parseName();
        if (!std.mem.eql(u8, tag.slice, closing_tag.slice)) {
            return error.NonMatchingClosingTag;
        }

        _ = reader.eatWs();
        try reader.expect('>');
    }

    const element = try allocator.create(@This());
    element.* = .{
        .tag = try allocator.dupe(u8, tag.slice),
        .attributes = try attributes.toOwnedSlice(),
        .children = try children.toOwnedSlice(),
        .line = tag.line,
        .column = tag.column,
    };
    return element;
}

pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(this.tag);

    for (this.children) |*child| {
        child.deinit(allocator);
    }
    allocator.free(this.children);

    for (this.attributes) |*attribute| {
        attribute.deinit(allocator);
    }
    allocator.free(this.attributes);
}

pub fn destroy(this: *@This(), allocator: std.mem.Allocator) void {
    this.deinit(allocator);
    allocator.destroy(this);
}

pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(" {}:{}<{s}", .{ this.line, this.column, this.tag });
    for (this.attributes) |a| {
        try writer.print(" {s}={s}", .{ a.name, a.value });
    }
    try writer.print(">", .{});
    for (this.children) |c| {
        try c.dumpString(writer);
    }
    // try writer.writeByte('\n');
}

fn writeIndent(w: *std.Io.Writer, indent: u32) !void {
    for (0..indent) |_| {
        try w.writeByte(' ');
    }
}

pub fn debugPrint(this: @This(), w: *std.Io.Writer, indent: u32) !void {
    try writeIndent(w, indent);
    try w.writeByte('<');
    _ = try w.write(this.tag);
    for (this.attributes) |a| {
        try w.print(" {s}={s}", .{ a.name, a.value });
    }
    try w.writeByte('>');
    try w.writeByte('\n');

    for (this.children) |*child| {
        switch (child.*) {
            .char_data => |char_data| {
                try writeIndent(w, indent + 2);
                try w.print("{s}\n", .{char_data});
            },
            .comment => |comment| {
                try writeIndent(w, indent + 2);
                try w.print(";; {s}\n", .{comment});
            },
            .element => |element| {
                try element.debugPrint(w, indent + 2);
            },
        }
        // child.debugPrint(w, indent + 2);
    }
}

pub fn getAttribute(this: @This(), attrib_name: []const u8) ?[]const u8 {
    for (this.attributes) |child| {
        if (std.mem.eql(u8, child.name, attrib_name)) {
            return child.value;
        }
    }

    return null;
}

// pub fn getCharData(this: @This(), child_tag: []const u8) ?[]const u8 {
//     const child = this.findChildByTag(child_tag) orelse return null;
//     if (child.children.len != 1) {
//         return null;
//     }
//
//     return switch (child.children[0]) {
//         .char_data => |char_data| char_data,
//         else => null,
//     };
// }

pub fn getCharData(this: @This()) []const u8 {
    return switch (this.children[0]) {
        .char_data => |char_data| char_data,
        else => @panic("no_char_data"),
    };
}

pub const ChildIterator = struct {
    items: []Content,
    i: usize,

    pub fn next(this: *ChildIterator) ?*Content {
        if (this.i < this.items.len) {
            this.i += 1;
            return &this.items[this.i - 1];
        }

        return null;
    }
};

pub fn iterator(this: @This()) ChildIterator {
    return .{
        .items = this.children,
        .i = 0,
    };
}

pub const ChildElementIterator = struct {
    inner: ChildIterator,

    pub fn next(this: *ChildElementIterator) ?*Element {
        while (this.inner.next()) |child| {
            if (child.* != .element) {
                continue;
            }

            return child.*.element;
        }

        return null;
    }
};

pub fn elements(this: @This()) ChildElementIterator {
    return .{
        .inner = this.iterator(),
    };
}

pub const FindChildrenByTagIterator = struct {
    inner: ChildElementIterator,
    tag: []const u8,

    pub fn next(this: *FindChildrenByTagIterator) ?*Element {
        while (this.inner.next()) |child| {
            if (!std.mem.eql(u8, child.tag, this.tag)) {
                continue;
            }

            return child;
        }

        return null;
    }
};

pub fn findChildrenByTag(this: @This(), tag: []const u8) FindChildrenByTagIterator {
    return .{
        .inner = this.elements(),
        .tag = tag,
    };
}

pub fn findChildByTag(this: @This(), tag: []const u8) ?*@This() {
    var it = this.findChildrenByTag(tag);
    return it.next();
}
