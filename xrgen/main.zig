const std = @import("std");
const xml = @import("xml");
const Args = @import("Args.zig");

pub fn main() !void {
    const args = try Args.init(std.os.argv);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    const xml_src = std.fs.cwd().readFileAlloc(
        allocator,
        args.xml_path,
        std.math.maxInt(usize),
    ) catch |err| {
        std.log.err(
            "Error: Failed to open input file '{s}' ({s})",
            .{ args.xml_path, @errorName(err) },
        );
        return error.fail_open_xml_path;
    };
    defer allocator.free(xml_src);

    var doc = try xml.parse(allocator, xml_src);
    defer doc.deinit();
}
