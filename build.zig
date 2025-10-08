const std = @import("std");

pub const android = @import("android/android.zig");
pub const cpp = @import("cpp/cpp.zig");
pub const getEnvPath = @import("util.zig").getEnvPath;
pub const windows = @import("windows/windows.zig");

pub fn build(b: *std.Build) void {
    _ = b; // stub
}
