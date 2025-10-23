const std = @import("std");
const zbk = @import("zbk");

pub fn build(b: *std.Build) !void {
    // const meson = try b.findProgram(&.{"meson"}, &.{});
    // try build_pkgconf(b, meson);
    // try build_gvdb(b, meson);
    // try build_gi(b, meson);

    const glib = zbk.cpp.MesonStep.create(b, .{
        .source = b.dependency("glib", .{}).path("").getPath(b),
    });
    const glib_install = b.addInstallDirectory(.{
        .source_dir = glib.getInstallPrefix(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    // b.getInstallStep().dependOn(&glib_install.step);

    const pkgconf = zbk.cpp.MesonStep.create(b, .{
        .source = b.dependency("pkgconf", .{}).path("").getPath(b),
    });
    pkgconf.step.dependOn(&glib_install.step);
    const pkgconf_install = b.addInstallDirectory(.{
        .source_dir = pkgconf.getInstallPrefix(),
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&pkgconf_install.step);
}

fn build_pkgconf(b: *std.Build, meson: []const u8) !void {
    const prefix = b.addNamedWriteFiles("prefix");

    const meson_setup = b.addSystemCommand(&.{ meson, "setup" });
    meson_setup.setName("meson_setup");
    const build_dir = meson_setup.addOutputDirectoryArg("build");
    meson_setup.addDirectoryArg(b.dependency("pkgconf", .{}).path(""));

    const meson_compile = b.addSystemCommand(&.{ meson, "compile", "-C" });
    meson_compile.setName("meson_compile");
    meson_compile.addDirectoryArg(build_dir);
    prefix.step.dependOn(&meson_compile.step);

    _ = prefix.addCopyFile(build_dir.path(b, "pkgconf.exe"), "bin/pkg-config.exe");
    _ = prefix.addCopyFile(build_dir.path(b, "pkgconf-7.dll"), "bin/pkgconf-7.dll");

    const install = b.addInstallDirectory(.{
        .source_dir = prefix.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    b.step("pkgconf", "build pkgconf to pkg-conf").dependOn(&install.step);
}

fn build_gvdb(b: *std.Build, meson: []const u8) !void {
    const meson_setup = b.addSystemCommand(&.{ meson, "setup" });
    meson_setup.setName("meson_setup");
    meson_setup.addPathDir("zig-out/bin");
    meson_setup.setEnvironmentVariable("PKG_CONFIG_PATH", "zig-out/lib/pkgconfig");
    meson_setup.addArg("--prefix");
    _ = meson_setup.addDirectoryArg(b.path("zig-out"));
    const meson_build_dir = meson_setup.addOutputDirectoryArg("build");
    meson_setup.addDirectoryArg(b.dependency("gvdb", .{}).path(""));

    const meson_compile = b.addSystemCommand(&.{ meson, "compile", "-C" });
    meson_compile.setName("meson_compile");
    meson_compile.addDirectoryArg(meson_build_dir);

    const meson_install = b.addSystemCommand(&.{ meson, "install", "-C" });
    meson_install.setName("meson_install");
    meson_install.step.dependOn(&meson_compile.step);
    meson_install.addDirectoryArg(meson_build_dir);

    b.step("gvdb", "build gvdb").dependOn(&meson_install.step);
}

fn build_gi(b: *std.Build, meson: []const u8) !void {
    const meson_setup = b.addSystemCommand(&.{ meson, "setup" });
    meson_setup.setName("meson_setup");
    meson_setup.addPathDir("zig-out/bin");
    meson_setup.setEnvironmentVariable("PKG_CONFIG_PATH", "zig-out/lib/pkgconfig");
    meson_setup.addArg("--prefix");
    _ = meson_setup.addDirectoryArg(b.path("zig-out"));
    const meson_build_dir = meson_setup.addOutputDirectoryArg("build");
    meson_setup.addDirectoryArg(b.dependency("gobject-introspection", .{}).path(""));

    const meson_compile = b.addSystemCommand(&.{ meson, "compile", "-C" });
    meson_compile.setName("meson_compile");
    meson_compile.addDirectoryArg(meson_build_dir);

    const meson_install = b.addSystemCommand(&.{ meson, "install", "-C" });
    meson_install.setName("meson_install");
    meson_install.step.dependOn(&meson_compile.step);
    meson_install.addDirectoryArg(meson_build_dir);

    b.step("gi", "build gobjct-introspection").dependOn(&meson_install.step);
}
