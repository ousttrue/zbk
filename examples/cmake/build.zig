const std = @import("std");
const zbk = @import("zbk");

pub fn build(b: *std.Build) void {
    const dll = zbk.cpp.CMakeStep.create(b, .{
        .source = b.path("dll").getPath(b),
        .use_vcenv = true,
    });

    const install = b.addInstallDirectory(.{
        .source_dir = dll.getInstallPrefix(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install.step);
}
