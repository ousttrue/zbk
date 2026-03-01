const std = @import("std");
const util = @import("../util.zig");
const getEnvPath = util.getEnvPath;
const ndk = @import("ndk.zig");

pub const SdkLocation = enum {
    // studio path
    androidstudio,
    // arch linux
    opt,
};

pub const JdkLocation = union(enum) {
    java_home: []const u8,
    bin_path: []const u8,
};

android_home: []const u8,
ndk_path: []const u8,
jdk_location: JdkLocation,

pub fn init(allocator: std.mem.Allocator, location: SdkLocation) !@This() {
    return switch (location) {
        .androidstudio => blk: {
            const android_home = getEnvPath(allocator, "ANDROID_HOME") orelse return error.NO_ANDROID_HOME;
            const ndk_path = try ndk.getPath(allocator, .{ .android_home = android_home });
            const java_home = getEnvPath(allocator, "JAVA_HOME") orelse return error.NO_JAVA_HOME;
            break :blk .{
                .android_home = android_home,
                .ndk_path = ndk_path,
                .jdk_location = .{ .java_home = java_home },
            };
        },
        .opt => .{
            .android_home = "/opt/android-sdk",
            .ndk_path = "/opt/android-sdk/ndk-bundle",
            .jdk_location = .{ .bin_path = "/usr/sbin" },
        },
    };
}
