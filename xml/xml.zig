const std = @import("std");
const Reader = @import("Reader.zig");
pub const Declaration = @import("Declaration.zig");
pub const Element = @import("Element.zig");

pub fn parseWithDecl(
    allocator: std.mem.Allocator,
    source: []const u8,
) Reader.ParseError!struct { *Element, ?*Declaration } {
    var reader = Reader{
        .source = source,
    };

    try reader.skipComments();

    const xml_decl = try Declaration.parse(allocator, &reader);
    _ = reader.eatWs();
    _ = reader.eatStr("<!DOCTYPE xml>");
    _ = reader.eatWs();

    // xr.xml currently has 2 processing instruction tags, they're handled manually for now
    if (try Declaration.parse(allocator, &reader)) |decl| {
        decl.destroy(allocator);
    }
    _ = reader.eatWs();
    if (try Declaration.parse(allocator, &reader)) |decl| {
        decl.destroy(allocator);
    }
    _ = reader.eatWs();

    try reader.skipComments();

    const root = try Element.parse(allocator, &reader);
    _ = reader.eatWs();
    try reader.skipComments();

    if (reader.peek() != null) return error.NotEnd;

    return .{
        root,
        xml_decl,
    };
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*Element {
    const root, const maybe_decl = try parseWithDecl(allocator, source);
    if (maybe_decl) |decl| {
        decl.destroy(allocator);
    }
    return root;
}

test "xml: Element.parse" {
    const a = std.testing.allocator;
    {
        var reader = Reader{ .source = "<= a='b'/>" };
        try std.testing.expectError(error.NonMatchingOpeningTag, Element.parse(a, &reader));
    }

    {
        const elem = try parse(a, "<python size='15' color = \"green\"/>");
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
        const elem = try parse(a, "<python>test</python>");
        defer elem.destroy(a);
        try std.testing.expectEqualSlices(u8, elem.tag, "python");
        try std.testing.expectEqualSlices(u8, elem.children[0].char_data, "test");
    }

    {
        const elem = try parse(a, "<a>b<c/>d<e/>f<!--g--></a>");
        defer elem.destroy(a);
        try std.testing.expectEqualSlices(u8, elem.tag, "a");
        try std.testing.expectEqualSlices(u8, elem.children[0].char_data, "b");
        try std.testing.expectEqualSlices(u8, elem.children[1].element.tag, "c");
        try std.testing.expectEqualSlices(u8, elem.children[2].char_data, "d");
        try std.testing.expectEqualSlices(u8, elem.children[3].element.tag, "e");
        try std.testing.expectEqualSlices(u8, elem.children[4].char_data, "f");
        try std.testing.expectEqualSlices(u8, elem.children[5].comment, "g");
    }

    {
        const elem = try parse(a, "<word>hello&amp;world</word>");
        defer elem.destroy(a);
        try std.testing.expectEqualSlices(u8, elem.children[0].char_data, "hello&world");
    }
}

test "xml: top level comments" {
    const a = std.testing.allocator;
    var root = try parse(
        a,
        "<?xml version='aa'?><!--comment--><python color='green'/><!--another comment-->",
    );
    defer root.destroy(a);
    try std.testing.expectEqualSlices(u8, "python", root.tag);

    std.testing.refAllDecls(Reader);
    std.testing.refAllDecls(Declaration);
    std.testing.refAllDecls(Element);
}
