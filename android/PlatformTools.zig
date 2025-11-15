const std = @import("std");

path: []const u8,

pub fn init(b: *std.Build, android_home: []const u8) !@This() {
    return @This(){
        .path = b.pathResolve(&.{ android_home, "platform-tools" }),
    };
}

pub fn adb_install(
    self: @This(),
    b: *std.Build,
    apk: std.Build.LazyPath,
) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.path, "adb.exe" }),
        "install",
        "-r",
    });
    run.addFileArg(apk);
    return run;
}

pub const StartOpts = struct { package_name: []const u8, activity_name: []const u8 = "android.app.NativeActivity" };

pub fn adb_start(
    self: @This(),
    b: *std.Build,
    opts: StartOpts,
) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.path, "adb.exe" }),
        "shell",
        "am",
        "start",
        "-S",
        "-W",
        "-n",
        b.fmt("{s}/{s}", .{ opts.package_name, opts.activity_name }),
    });
    return run;
}
