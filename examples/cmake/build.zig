const std = @import("std");
const zbk = @import("zbk");

pub fn build(b: *std.Build) void {
    const dll = zbk.cpp.cmake.build(b, .{
        .source = b.path("dll"),
        .use_vcenv = true,
    });

    const install = b.addInstallDirectory(.{
        .source_dir = dll.prefix.getDirectory(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install.step);
}
