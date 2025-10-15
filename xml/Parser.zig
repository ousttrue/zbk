const std = @import("std");
const Reader = @import("Reader.zig");
const Document = @import("Document.zig");

pub const ParseError = error{
    IllegalCharacter,
    UnexpectedEof,
    UnexpectedCharacter,
    UnclosedValue,
    UnclosedComment,
    InvalidName,
    InvalidEntity,
    InvalidStandaloneValue,
    NonMatchingClosingTag,
    InvalidDocument,
    OutOfMemory,
};

allocator: std.mem.Allocator,
reader: Reader,

pub fn init(allocator: std.mem.Allocator, source: []const u8) @This() {
    return @This(){
        .allocator = allocator,
        .reader = .{ .source = source },
    };
}

pub fn parseElement(this: *@This()) !?*Document.Element {
    const start = this.reader.offset;

    if (!this.reader.eat('<')) return null;

    const tag = this.reader.parseName() catch {
        this.reader.offset = start;
        return null;
    };

    var attributes = std.array_list.Managed(Document.Attribute).init(this.allocator);
    defer attributes.deinit();

    var children = std.array_list.Managed(Document.Content).init(this.allocator);
    defer children.deinit();

    while (this.reader.eatWs()) {
        const attr = (try this.parseAttr()) orelse break;
        try attributes.append(attr);
    }

    if (!this.reader.eatStr("/>")) {
        try this.reader.expect('>');

        while (true) {
            if (this.reader.peek() == null) {
                return error.UnexpectedEof;
            } else if (this.reader.eatStr("</")) {
                break;
            }

            const content = try this.parseContent();
            try children.append(content);
        }

        const closing_tag = try this.reader.parseName();
        if (!std.mem.eql(u8, tag.slice, closing_tag.slice)) {
            return error.NonMatchingClosingTag;
        }

        _ = this.reader.eatWs();
        try this.reader.expect('>');
    }

    const element = try this.allocator.create(Document.Element);
    element.* = .{
        .tag = try this.allocator.dupe(u8, tag.slice),
        .attributes = try attributes.toOwnedSlice(),
        .children = try children.toOwnedSlice(),
        .line = tag.line,
        .column = tag.column,
    };
    return element;
}

pub fn parseDeclaration(this: *@This()) !?*Document.Declaration {
    const start = this.reader.offset;

    if (!this.reader.eatStr("<?")) return null;

    const tag = this.reader.parseName() catch {
        this.reader.offset = start;
        return null;
    };

    var attributes = std.array_list.Managed(Document.Attribute).init(this.allocator);
    defer attributes.deinit();

    var children = std.array_list.Managed(Document.Content).init(this.allocator);
    defer children.deinit();

    while (this.reader.eatWs()) {
        const attr = (try this.parseAttr()) orelse break;
        try attributes.append(attr);
    }

    try this.reader.expectStr("?>");

    const element = try this.allocator.create(Document.Declaration);
    element.* = .{
        .tag = try this.allocator.dupe(u8, tag.slice),
        .attributes = try attributes.toOwnedSlice(),
        .children = try children.toOwnedSlice(),
        .line = tag.line,
        .column = tag.column,
    };
    return element;
}

fn parseContent(this: *@This()) ParseError!Document.Content {
    if (try this.reader.allocParseCharData(this.allocator)) |cd| {
        return Document.Content{ .char_data = cd };
    } else if (try this.reader.parseComment()) |comment| {
        return Document.Content{ .comment = try this.allocator.dupe(u8, comment) };
    } else if (try this.parseElement()) |elem| {
        return Document.Content{ .element = elem };
    } else {
        return error.UnexpectedCharacter;
    }
}

fn parseAttr(this: *@This()) !?Document.Attribute {
    const name = this.reader.parseName() catch return null;
    _ = this.reader.eatWs();
    try this.reader.expect('=');
    _ = this.reader.eatWs();
    const value = try this.reader.allocParseAttrValue(this.allocator);

    const attr = Document.Attribute{
        .name = try this.allocator.dupe(u8, name.slice),
        .value = value,
    };
    return attr;
}
