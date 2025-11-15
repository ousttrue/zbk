const std = @import("std");

pub const android = @import("android/android.zig");
pub const cpp = @import("cpp/cpp.zig");
const util = @import("util.zig");
pub const getEnvPath = util.getEnvPath;
pub const windows = @import("windows/windows.zig");
pub const openxr = @import("xrgen/build_openxr.zig");

pub fn build(b: *std.Build) !void {
    openxr.build_xrgen(b);
}
