const std = @import("std");
const zbk = @import("zbk");

pub fn build(b: *std.Build) void {
    const zbk_dep = b.dependency("zbk", .{});

    const vcenv_wf = zbk_dep.namedWriteFiles("vcenv");
    const vcenv = vcenv_wf.getDirectory().path(b, "vcenv");

    const dll = zbk.cpp.cmake.build(b, .{
        .source = b.path("dll"),
        .vcenv = vcenv,
    });

    const install = b.addInstallDirectory(.{
        .source_dir = dll.prefix.getDirectory(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install.step);
}
