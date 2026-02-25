const std = @import("std");
const zbk = @import("zbk");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const dll = zbk.cpp.CMakeStep.create(b, .{
        .source = b.path("dll").getPath(b),
        .use_vcenv = target.result.os.tag == .windows,
    });

    const install = b.addInstallDirectory(.{
        .source_dir = dll.getInstallPrefix(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install.step);
}
