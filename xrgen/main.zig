const std = @import("std");
const xml = @import("xml");
const Args = @import("Args.zig");
const Registry = @import("registry/Registry.zig");

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

    var root = try xml.parse(allocator, xml_src);
    defer root.destroy(allocator);

    // var registry = Registry{ .allocator = allocator };
    // defer registry.deinit();
    // try registry.load(root);

    // types
    // enums*
    // commands*
    // interaction_profiles
    // feature*
    // extensions

    // root/
    //   xr.zig
    //   c.zig (translateC from openxr/openxr.h)
    //   features/
    //     XR_VERSION_1_0.zig
    //     XR_LOADER_VERSION_1_0.zig
    //     XR_VERSION_1_1.zig
    //   extensions
    //     XR_KHR_android_thread_settings.zig
    //     ...

    const out_dir = try std.fs.cwd().openDir(args.out_path, .{ .access_sub_paths = true });

    {
        var it = root.findChildrenByTag("feature");
        while (it.next()) |feature| {
            // std.log.debug("{f}", .{feature});
            const name = feature.getAttribute("name").?;
            const path = try std.fmt.allocPrint(allocator, "features/{s}.zig", .{name});
            defer allocator.free(path);
            try writeFile(out_dir, path, "");
        }
    }

    if (root.findChildByTag("extensions")) |extensions| {
        var file = try openFile(out_dir, "extensions/extensions.zig");
        defer file.close();
        var buf: [1024]u8 = undefined;
        var writer = file.writer(&buf);
        defer writer.interface.flush() catch @panic("OOM");

        var it = extensions.findChildrenByTag("extension");
        while (it.next()) |extension| {
            if (extension.getAttribute("supported")) |supported| {
                if (std.mem.eql(u8, "openxr", supported)) {
                    const name = try writeExtension(allocator, out_dir, extension);
                    try writer.interface.print(
                        \\pub const {s} = @import("{s}.zig");
                        \\
                    , .{ name, name });
                } else if (std.mem.eql(u8, "disabled", supported)) {
                    // skip
                } else {
                    std.log.err("{f}", .{extension});
                    @panic("unknown supported");
                }
            }
        }
    }

    {
        var file = try openFile(out_dir, "xr.zig");
        defer file.close();

        try file.writeAll(
            \\const std = @import("std");
            \\pub const c = @import("c");
            \\pub const extensions = @import("extensions/extensions.zig");
            \\
            \\
        );
        try file.writeAll(@embedFile("snippets.zig"));
        try file.writeAll("\n");
    }
}

fn writeFile(
    cwd: std.fs.Dir,
    out_path: []const u8,
    content: []const u8,
) !void {
    var file = try openFile(cwd, out_path);
    defer file.close();
    var buf: [1024]u8 = undefined;
    var writer = file.writer(&buf);

    try writer.interface.writeAll(content);
}

fn writeExtension(
    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    extension: *const xml.Element,
) ![]const u8 {
    const name = extension.getAttribute("name").?;
    const out_path = try std.fmt.allocPrint(allocator, "extensions/{s}.zig", .{name});
    defer allocator.free(out_path);
    var file = try openFile(cwd, out_path);
    defer file.close();
    var buf: [1024]u8 = undefined;
    var writer = file.writer(&buf);
    defer writer.interface.flush() catch @panic("OOM");

    try writer.interface.writeAll(
        \\const c = @import("c");
        \\
        \\
    );

    if (extension.findChildByTag("require")) |require| {
        // std.log.debug("{f}", .{extension});
        var it = require.findChildrenByTag("command");
        while (it.next()) |command| {
            const command_name = command.getAttribute("name").?;
            // std.log.debug("{s}", .{command_name});
            try writer.interface.print(
                \\{s}: c.PFN_{s} = null,
                \\
            , .{ command_name, command_name });
        }
    }

    return name;
}

fn openFile(cwd: std.fs.Dir, out_path: []const u8) !std.fs.File {
    if (std.fs.path.dirname(out_path)) |dir| {
        cwd.access(dir, .{}) catch {
            try cwd.makePath(dir);
        };
    }
    return try cwd.createFile(out_path, .{});
}

fn formatZigSource(allocator: std.mem.Allocator, src: [:0]u8) ![]const u8 {
    var tree = try std.zig.Ast.parse(allocator, src, .zig);
    defer tree.deinit(allocator);
    for (tree.errors) |e| {
        std.log.debug("{s}", .{@tagName(e.tag)});
    }
    var formatted = std.Io.Writer.Allocating.init(allocator);
    defer formatted.deinit();
    try tree.render(allocator, &formatted.writer, .{});
    const zig_src = try formatted.toOwnedSlice();
    return zig_src;
}
