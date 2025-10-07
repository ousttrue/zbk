const std = @import("std");

pub const android = @import("android/android.zig");
pub const cpp = @import("cpp/cpp.zig");

pub fn getEnvPath(allocator: std.mem.Allocator, env_name: []const u8) ![]const u8 {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    const env_path = try allocator.dupe(u8, env.get(env_name) orelse {
        return error.no_android_home;
    });
    for (env_path) |*ch| {
        if (ch.* == '\\') {
            ch.* = '/';
        }
    }
    return env_path;
}

pub fn build(b: *std.Build) void {
    _ = b; // stub
}
