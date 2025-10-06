const std = @import("std");
const c = @cImport({
    @cInclude("android/native_activity.h");
    @cInclude("android/log.h");
});

const tag = "zbk";

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const priority = switch (message_level) {
        .err => c.ANDROID_LOG_ERROR,
        .warn => c.ANDROID_LOG_WARN,
        .info => c.ANDROID_LOG_INFO,
        .debug => c.ANDROID_LOG_DEBUG,
    };
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";

    var buf = std.io.FixedBufferStream([4 * 1024]u8){
        .buffer = undefined,
        .pos = 0,
    };
    var writer = buf.writer();
    writer.print(prefix ++ format, args) catch {};

    if (buf.pos >= buf.buffer.len) {
        buf.pos = buf.buffer.len - 1;
    }
    buf.buffer[buf.pos] = 0;

    _ = c.__android_log_write(priority, tag, &buf.buffer);
}

export fn ANativeActivity_onCreate(
    activity: *c.ANativeActivity,
    savedState: *anyopaque,
    savedStateSize: usize,
) void {
    _ = activity;
    _ = savedState;
    _ = savedStateSize;
    std.log.debug("ANativeActivity: onCreate !", .{});
}
