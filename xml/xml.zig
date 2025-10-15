const std = @import("std");
const Parser = @import("Parser.zig");
pub const Document = @import("Document.zig");

pub fn parse(allocator: std.mem.Allocator, src: []const u8) !Document {
    var parser = Parser.init(allocator, src);

    try parser.reader.skipComments();

    const xml_decl = try Document.Declaration.parse(allocator, &parser.reader);
    _ = parser.reader.eatWs();
    _ = parser.reader.eatStr("<!DOCTYPE xml>");
    _ = parser.reader.eatWs();

    // xr.xml currently has 2 processing instruction tags, they're handled manually for now
    if (try Document.Declaration.parse(allocator, &parser.reader)) |decl| {
        decl.destroy(allocator);
    }
    _ = parser.reader.eatWs();
    if (try Document.Declaration.parse(allocator, &parser.reader)) |decl| {
        decl.destroy(allocator);
    }
    _ = parser.reader.eatWs();

    try parser.reader.skipComments();

    const root = (try Document.Element.parse(allocator, &parser.reader)) orelse return error.InvalidDocument;
    _ = parser.reader.eatWs();
    try parser.reader.skipComments();

    if (parser.reader.peek() != null) return error.InvalidDocument;

    return Document{
        .allocator = allocator,
        .xml_decl = xml_decl,
        .root = root,
    };
}

test "xml: Element.parse" {
    const a = std.testing.allocator;
    {
        var parser = Parser.init(a, "<= a='b'/>");
        const elem = try Document.Element.parse(parser.allocator, &parser.reader);
        try std.testing.expectEqual(@as(?*Document.Element, null), elem);
        try std.testing.expectEqual(@as(?u8, '<'), parser.reader.peek());
    }

    {
        var parser = Parser.init(a, "<python size='15' color = \"green\"/>");
        const elem = (try Document.Element.parse(parser.allocator, &parser.reader)).?;
        defer elem.destroy(a);
        try std.testing.expectEqualSlices(u8, elem.tag, "python");

        const size_attr = elem.attributes[0];
        try std.testing.expectEqualSlices(u8, size_attr.name, "size");
        try std.testing.expectEqualSlices(u8, size_attr.value, "15");

        const color_attr = elem.attributes[1];
        try std.testing.expectEqualSlices(u8, color_attr.name, "color");
        try std.testing.expectEqualSlices(u8, color_attr.value, "green");
    }

    {
        var parser = Parser.init(a, "<python>test</python>");
        const elem = (try Document.Element.parse(parser.allocator, &parser.reader)).?;
        defer elem.destroy(a);
        try std.testing.expectEqualSlices(u8, elem.tag, "python");
        try std.testing.expectEqualSlices(u8, elem.children[0].char_data, "test");
    }

    {
        var parser = Parser.init(a, "<a>b<c/>d<e/>f<!--g--></a>");
        const elem = (try Document.Element.parse(parser.allocator, &parser.reader)).?;
        defer elem.destroy(a);
        try std.testing.expectEqualSlices(u8, elem.tag, "a");
        try std.testing.expectEqualSlices(u8, elem.children[0].char_data, "b");
        try std.testing.expectEqualSlices(u8, elem.children[1].element.tag, "c");
        try std.testing.expectEqualSlices(u8, elem.children[2].char_data, "d");
        try std.testing.expectEqualSlices(u8, elem.children[3].element.tag, "e");
        try std.testing.expectEqualSlices(u8, elem.children[4].char_data, "f");
        try std.testing.expectEqualSlices(u8, elem.children[5].comment, "g");
    }
}

test "xml: parse prolog" {
    const a = std.testing.allocator;

    {
        var parser = Parser.init(a, "<?xmla version='aa'?>");
        const decl = (try Document.Declaration.parse(parser.allocator, &parser.reader)).?;
        defer decl.destroy(a);
        try std.testing.expectEqualSlices(u8, decl.tag, "xmla");
        try std.testing.expectEqualSlices(u8, "aa", decl.getAttribute("version").?);
    }

    {
        var parser = Parser.init(a, "<?xml version='aa'?>");
        const decl = (try Document.Declaration.parse(parser.allocator, &parser.reader)).?;
        defer decl.destroy(a);
        try std.testing.expectEqualSlices(u8, "aa", decl.getAttribute("version").?);
        try std.testing.expectEqual(@as(?[]const u8, null), decl.getAttribute("encoding"));
        try std.testing.expectEqual(@as(?[]const u8, null), decl.getAttribute("standalone"));
    }

    {
        var parser = Parser.init(a, "<?xml version=\"ccc\" encoding = 'bbb' standalone   \t =   'yes'?>");
        const decl = (try Document.Declaration.parse(parser.allocator, &parser.reader)).?;
        defer decl.destroy(a);
        try std.testing.expectEqualSlices(u8, "ccc", decl.getAttribute("version").?);
        try std.testing.expectEqualSlices(u8, "bbb", decl.getAttribute("encoding").?);
        try std.testing.expectEqualSlices(u8, "yes", decl.getAttribute("standalone").?);
    }
}

test "xml: top level comments" {
    var doc = try parse(
        std.testing.allocator,
        "<?xml version='aa'?><!--comment--><python color='green'/><!--another comment-->",
    );
    defer doc.deinit();
    try std.testing.expectEqualSlices(u8, "python", doc.root.tag);
}
