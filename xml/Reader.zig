const std = @import("std");

source: []const u8,
offset: usize = 0,
line: usize = 0,
column: usize = 0,

pub fn consumeNoEof(this: *@This()) u8 {
    std.debug.assert(this.offset < this.source.len);
    const c = this.source[this.offset];
    this.offset += 1;

    if (c == '\n') {
        this.line += 1;
        this.column = 0;
    } else {
        this.column += 1;
    }

    return c;
}

pub fn expectStr(this: *@This(), text: []const u8) !void {
    if (this.source.len < this.offset + text.len) {
        return error.UnexpectedEof;
    } else if (std.mem.startsWith(u8, this.source[this.offset..], text)) {
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            _ = this.consumeNoEof();
        }

        return;
    }

    return error.UnexpectedCharacter;
}

pub fn eatStr(this: *@This(), text: []const u8) bool {
    this.expectStr(text) catch return false;
    return true;
}

pub fn expect(this: *@This(), expected: u8) !void {
    if (this.peek()) |actual| {
        if (expected != actual) {
            return error.UnexpectedCharacter;
        }

        _ = this.consumeNoEof();
        return;
    }

    return error.UnexpectedEof;
}

pub fn consume(this: *@This()) !u8 {
    if (this.offset < this.source.len) {
        return this.consumeNoEof();
    }

    return error.UnexpectedEof;
}

pub fn allocParseAttrValue(this: *@This(), allocator: std.mem.Allocator) ![]const u8 {
    const quote = try this.consume();
    if (quote != '"' and quote != '\'') return error.UnexpectedCharacter;

    const begin = this.offset;

    while (true) {
        const c = this.consume() catch return error.UnclosedValue;
        if (c == quote) break;
    }

    const end = this.offset - 1;

    return try allocUnescape(allocator, this.source[begin..end]);
}

pub fn parseEqAttrValue(this: *@This()) ![]const u8 {
    _ = this.eatWs();
    try this.expect('=');
    _ = this.eatWs();

    return try this.parseAttrValue();
}

pub fn eat(this: *@This(), char: u8) bool {
    this.expect(char) catch return false;
    return true;
}

pub fn expectWs(this: *@This()) !void {
    if (!this.eatWs()) return error.UnexpectedCharacter;
}

pub fn currentLine(this: @This()) []const u8 {
    var begin: usize = 0;
    if (std.mem.lastIndexOfScalar(u8, this.source[0..this.offset], '\n')) |prev_nl| {
        begin = prev_nl + 1;
    }

    const end = std.mem.indexOfScalarPos(u8, this.source, this.offset, '\n') orelse this.source.len;
    return this.source[begin..end];
}

pub fn parseComment(this: *@This()) !?[]const u8 {
    if (!this.eatStr("<!--")) return null;

    const begin = this.offset;
    while (!this.eatStr("-->")) {
        _ = this.consume() catch return error.UnclosedComment;
    }

    const end = this.offset - "-->".len;
    return this.source[begin..end];
}

pub fn peek(this: *@This()) ?u8 {
    return if (this.offset < this.source.len) this.source[this.offset] else null;
}

// white space
pub fn eatWs(this: *@This()) bool {
    var ws = false;

    while (this.peek()) |ch| {
        switch (ch) {
            ' ', '\t', '\n', '\r' => {
                ws = true;
                _ = this.consumeNoEof();
            },
            else => break,
        }
    }

    return ws;
}

pub fn skipComments(this: *@This()) !void {
    while ((try this.parseComment())) |_| {
        _ = this.eatWs();
    }
}

const Token = struct {
    line: usize,
    column: usize,
    slice: []const u8,
};

pub fn parseName(parser: *@This()) !Token {
    // XML's spec on names is very long, so to make this easier
    // we just take any character that is not special and not whitespace
    const line = parser.line;
    const column = parser.column;
    const begin = parser.offset;

    while (parser.peek()) |ch| {
        switch (ch) {
            ' ', '\t', '\n', '\r' => break,
            '&', '"', '\'', '<', '>', '?', '=', '/' => break,
            else => _ = parser.consumeNoEof(),
        }
    }

    const end = parser.offset;
    if (begin == end) return error.InvalidName;

    return .{
        .line = line,
        .column = column,
        .slice = parser.source[begin..end],
    };
}

pub fn allocParseCharData(this: *@This(), allocator: std.mem.Allocator) !?[]const u8 {
    const begin = this.offset;

    while (this.peek()) |ch| {
        switch (ch) {
            '<' => break,
            else => _ = this.consumeNoEof(),
        }
    }

    const end = this.offset;
    if (begin == end) return null;

    return try allocUnescape(allocator, this.source[begin..end]);
}

pub fn allocUnescape(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '&') {
            const entity_end = 1 + (std.mem.indexOfScalarPos(u8, text, i, ';') orelse return error.InvalidEntity);
            try buf.append(try unescapeEntity(text[i..entity_end]));
            i = entity_end;
        } else {
            try buf.append(text[i]);
            i += 1;
        }
    }

    return buf.toOwnedSlice();
}

test "unescape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectEqualSlices(u8, "test", try allocUnescape(a, "test"));
    try std.testing.expectEqualSlices(
        u8,
        "a<b&c>d\"e'f<",
        try allocUnescape(a, "a&lt;b&amp;c&gt;d&quot;e&apos;f&lt;"),
    );
    try std.testing.expectError(error.InvalidEntity, allocUnescape(a, "python&"));
    try std.testing.expectError(error.InvalidEntity, allocUnescape(a, "python&&"));
    try std.testing.expectError(error.InvalidEntity, allocUnescape(a, "python&test;"));
    try std.testing.expectError(error.InvalidEntity, allocUnescape(a, "python&boa"));
}

pub fn unescapeEntity(text: []const u8) !u8 {
    const EntitySubstition = struct { text: []const u8, replacement: u8 };

    const entities = [_]EntitySubstition{
        .{ .text = "&lt;", .replacement = '<' },
        .{ .text = "&gt;", .replacement = '>' },
        .{ .text = "&amp;", .replacement = '&' },
        .{ .text = "&apos;", .replacement = '\'' },
        .{ .text = "&quot;", .replacement = '"' },
    };

    for (entities) |entity| {
        if (std.mem.eql(u8, text, entity.text)) return entity.replacement;
    }

    return error.InvalidEntity;
}

test "xml: Reader" {
    {
        var parser = @This(){ .source = "I like pythons" };
        try std.testing.expectEqual(@as(?u8, 'I'), parser.peek());
        try std.testing.expectEqual(@as(u8, 'I'), parser.consumeNoEof());
        try std.testing.expectEqual(@as(?u8, ' '), parser.peek());
        try std.testing.expectEqual(@as(u8, ' '), try parser.consume());

        try std.testing.expect(parser.eat('l'));
        try std.testing.expectEqual(@as(?u8, 'i'), parser.peek());
        try std.testing.expectEqual(false, parser.eat('a'));
        try std.testing.expectEqual(@as(?u8, 'i'), parser.peek());

        try parser.expect('i');
        try std.testing.expectEqual(@as(?u8, 'k'), parser.peek());
        try std.testing.expectError(error.UnexpectedCharacter, parser.expect('a'));
        try std.testing.expectEqual(@as(?u8, 'k'), parser.peek());

        try std.testing.expect(parser.eatStr("ke"));
        try std.testing.expectEqual(@as(?u8, ' '), parser.peek());

        try std.testing.expect(parser.eatWs());
        try std.testing.expectEqual(@as(?u8, 'p'), parser.peek());
        try std.testing.expectEqual(false, parser.eatWs());
        try std.testing.expectEqual(@as(?u8, 'p'), parser.peek());

        try std.testing.expectEqual(false, parser.eatStr("aaaaaaaaa"));
        try std.testing.expectEqual(@as(?u8, 'p'), parser.peek());

        try std.testing.expectError(error.UnexpectedEof, parser.expectStr("aaaaaaaaa"));
        try std.testing.expectEqual(@as(?u8, 'p'), parser.peek());
        try std.testing.expectError(error.UnexpectedCharacter, parser.expectStr("pytn"));
        try std.testing.expectEqual(@as(?u8, 'p'), parser.peek());
        try parser.expectStr("python");
        try std.testing.expectEqual(@as(?u8, 's'), parser.peek());
    }

    {
        var parser = @This(){ .source = "" };
        try std.testing.expectEqual(parser.peek(), null);
        try std.testing.expectError(error.UnexpectedEof, parser.consume());
        try std.testing.expectEqual(parser.eat('p'), false);
        try std.testing.expectError(error.UnexpectedEof, parser.expect('p'));
    }
}
