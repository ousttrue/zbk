const std = @import("std");
const Reader = @import("Reader.zig");

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,

    fn parse(allocator: std.mem.Allocator, reader: *Reader) !?@This() {
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
};

pub const Content = union(enum) {
    char_data: []const u8,
    comment: []const u8,
    element: *Element,
};

pub const Declaration = struct {
    tag: []const u8,
    attributes: []Attribute = &.{},
    children: []Content = &.{},
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

        var children = std.array_list.Managed(Content).init(allocator);
        defer children.deinit();

        while (reader.eatWs()) {
            const attr = (try Attribute.parse(allocator, reader)) orelse break;
            try attributes.append(attr);
        }

        try reader.expectStr("?>");

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

    fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(this.tag);
        for (this.children) |child| {
            switch (child) {
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
        allocator.free(this.children);

        for (this.attributes) |attribute| {
            allocator.free(attribute.name);
            allocator.free(attribute.value);
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
};

pub const Element = struct {
    tag: []const u8,
    attributes: []Attribute = &.{},
    children: []Content = &.{},
    line: usize,
    column: usize,

    fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(this.tag);
        for (this.children) |child| {
            switch (child) {
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
        allocator.free(this.children);

        for (this.attributes) |attribute| {
            allocator.free(attribute.name);
            allocator.free(attribute.value);
        }
        allocator.free(this.attributes);
    }

    pub fn destroy(this: *@This(), allocator: std.mem.Allocator) void {
        this.deinit(allocator);
        allocator.destroy(this);
    }

    pub fn format(this: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("<{s} {}:{}", .{ this.tag, this.line, this.column });
        for (this.attributes) |a| {
            try writer.print(" {s}={s}", .{ a.name, a.value });
        }
        try writer.print(">", .{});
        for (this.children) |c| {
            switch (c) {
                .char_data => |char_data| try writer.print("{s}", .{char_data}),
                .comment => |comment| try writer.print("{s}", .{comment}),
                .element => |element| {
                    _ = element;
                    // try writer.print("{f}", .{element});
                },
            }
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

    pub fn getCharData(this: @This(), child_tag: []const u8) ?[]const u8 {
        const child = this.findChildByTag(child_tag) orelse return null;
        if (child.children.len != 1) {
            return null;
        }

        return switch (child.children[0]) {
            .char_data => |char_data| char_data,
            else => null,
        };
    }

    pub fn iterator(this: @This()) ChildIterator {
        return .{
            .items = this.children,
            .i = 0,
        };
    }

    pub fn elements(this: @This()) ChildElementIterator {
        return .{
            .inner = this.iterator(),
        };
    }

    pub fn findChildByTag(this: @This(), tag: []const u8) ?*@This() {
        var it = this.findChildrenByTag(tag);
        return it.next();
    }

    pub fn findChildrenByTag(this: @This(), tag: []const u8) FindChildrenByTagIterator {
        return .{
            .inner = this.elements(),
            .tag = tag,
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

    pub const ChildElementIterator = struct {
        inner: ChildIterator,

        pub fn next(this: *ChildElementIterator) ?*@This() {
            while (this.inner.next()) |child| {
                if (child.* != .element) {
                    continue;
                }

                return child.*.element;
            }

            return null;
        }
    };

    pub const FindChildrenByTagIterator = struct {
        inner: ChildElementIterator,
        tag: []const u8,

        pub fn next(this: *FindChildrenByTagIterator) ?*@This() {
            while (this.inner.next()) |child| {
                if (!std.mem.eql(u8, child.tag, this.tag)) {
                    continue;
                }

                return child;
            }

            return null;
        }
    };

    pub fn parse(allocator: std.mem.Allocator, reader: *Reader) !?*@This() {
        const start = reader.offset;

        if (!reader.eat('<')) return null;

        const tag = reader.parseName() catch {
            reader.offset = start;
            return null;
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

                const content = try parseContent(allocator, reader);
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

    fn parseContent(allocator: std.mem.Allocator, reader: *Reader) Reader.ParseError!Content {
        if (try reader.allocParseCharData(allocator)) |cd| {
            return Content{ .char_data = cd };
        } else if (try reader.parseComment()) |comment| {
            return Content{ .comment = try allocator.dupe(u8, comment) };
        } else if (try Element.parse(allocator, reader)) |elem| {
            return Content{ .element = elem };
        } else {
            return error.UnexpectedCharacter;
        }
    }
};

allocator: std.mem.Allocator,
xml_decl: ?*Declaration = null,
root: *Element,

pub fn deinit(this: *@This()) void {
    if (this.xml_decl) |xml_decl| {
        xml_decl.deinit(this.allocator);
        this.allocator.destroy(xml_decl);
    }
    this.root.deinit(this.allocator);
    this.allocator.destroy(this.root);
}
