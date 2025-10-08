const std = @import("std");
const zbk = @import("zbk");

pub fn build(b: *std.Build) !void {
    const vcenv = try zbk.windows.VcEnv.init(b.allocator);

    const dll = try zbk.cpp.cmake.build(b, .{
        .source = b.path("dll"),
        .envmap = vcenv.envmap,
    });

    const install = b.addInstallDirectory(.{
        .source_dir = dll.prefix.getDirectory(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install.step);
}
