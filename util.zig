const std = @import("std");

pub fn getEnvPath(allocator: std.mem.Allocator, env_name: []const u8) ?[]const u8 {
    var env = std.process.getEnvMap(allocator) catch @panic("OOM");
    defer env.deinit();

    const env_value = env.get(env_name) orelse {
        return null;
    };
    const env_path = allocator.dupe(u8, env_value) catch @panic("OOM");

    for (env_path) |*ch| {
        if (ch.* == '\\') {
            ch.* = '/';
        }
    }
    return env_path;
}
