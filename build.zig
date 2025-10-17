const std = @import("std");

pub const android = @import("android/android.zig");
pub const cpp = @import("cpp/cpp.zig");
pub const getEnvPath = @import("util.zig").getEnvPath;
pub const windows = @import("windows/windows.zig");
pub const openxr = @import("xrgen/build_openxr.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (b.graph.host.result.os.tag == .windows) {
        if (windows.getVswhere(b.allocator)) |vswhere| {
            if (windows.getVcInstall(b.allocator, vswhere)) |vcinstall| {
                const bat = b.fmt("{s}/VC/Auxiliary/Build/vcvars64.bat", .{vcinstall});
                // std.log.debug("bat => {s}", .{bat});
                const run = b.addSystemCommand(&.{ "cmd.exe", "/c", bat, "&", "set" });

                const wf = b.addNamedWriteFiles("vcenv");
                _ = wf.addCopyFile(run.captureStdOut(), "vcenv");
            }
        }
    }

    openxr.build_xrgen(b, target, optimize);
}
