const std = @import("std");
const sokol = @import("sokol");
const zbk = @import("zbk");
const ndk = zbk.android.ndk;
const API_LEVEL = 35;
const PKG_NAME = "com.zbk.sokol_cube";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    std.log.debug("build target: {s}", .{try target.result.linuxTriple(b.allocator)});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const mod_sokol = dep_sokol.module("sokol");
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});

    // call shdc.createModule() helper function, this returns a `!*Build.Module`:
    const mod_shd = try sokol.shdc.createModule(b, "shader", mod_sokol, .{
        .shdc_dep = dep_shdc,
        .input = "src/cube.glsl",
        .output = "shader.zig",
        .slang = if (target.result.abi.isAndroid())
            .{ .glsl310es = true }
        else
            .{ .hlsl5 = true },
    });

    const root_module = b.addModule("cube", .{
        .root_source_file = if (target.result.abi.isAndroid())
            b.path("src/android_main.zig")
        else
            b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = mod_sokol },
            .{ .name = "shader", .module = mod_shd },
        },
    });

    const bin = if (target.result.abi.isAndroid())
        b.addLibrary(.{
            .name = "cube",
            .root_module = root_module,
            .linkage = .dynamic,
        })
    else
        b.addExecutable(.{
            .name = "cube",
            .root_module = root_module,
        });
    b.installArtifact(bin);

    if (target.result.abi.isAndroid()) {
        const android_home = try zbk.getEnvPath(b.allocator, "ANDROID_HOME");
        const ndk_path = try ndk.getPath(b, .{ .android_home = android_home });
        const java_home = try zbk.getEnvPath(b.allocator, "JAVA_HOME");

        // error: error: unable to provide libc for target 'aarch64-linux.5.10...6.16-android.29'
        const libc_file = try ndk.LibCFile.make(b, ndk_path, target, API_LEVEL);
        // for compile
        bin.addSystemIncludePath(.{ .cwd_relative = libc_file.include_dir });
        bin.addSystemIncludePath(.{ .cwd_relative = libc_file.sys_include_dir });
        // for link
        bin.setLibCFile(libc_file.path);
        bin.addLibraryPath(.{ .cwd_relative = libc_file.crt_dir });
        bin.linkSystemLibrary("android");
        bin.linkSystemLibrary("log");
        // sokol use ndk
        const sokol_clib = dep_sokol.artifact("sokol_clib");
        sokol_clib.addSystemIncludePath(.{ .cwd_relative = libc_file.include_dir });
        sokol_clib.addSystemIncludePath(.{ .cwd_relative = libc_file.sys_include_dir });
        sokol_clib.setLibCFile(libc_file.path);
        sokol_clib.addLibraryPath(.{ .cwd_relative = libc_file.crt_dir });

        // android sdk
        const apk_builder = try zbk.android.ApkBuilder.init(b, .{
            .android_home = android_home,
            .java_home = java_home,
            .api_level = API_LEVEL,
        });

        const keystore_password = "example_password";
        const keystore = apk_builder.jdk.makeKeystore(b, keystore_password);

        // make apk from
        const apk = apk_builder.makeApk(b, .{
            .copy_list = &.{.{ .src = bin.getEmittedBin() }},
            .android_manifest = try apk_builder.generateAndroidManifest(b, PKG_NAME, bin.name),
            .keystore_password = keystore_password,
            .keystore_file = keystore.output,
            .resource_dir = b.path("res"),
        });
        const install = b.addInstallFile(apk, "bin/cube.apk");
        b.getInstallStep().dependOn(&install.step);

        // adb install
        // adb run
        const run_step = b.step("run", "Install and run the application on an Android device");
        const adb_install = apk_builder.platform_tools.adb_install(b, install.source);
        const adb_start = apk_builder.platform_tools.adb_start(b, .{ .package_name = PKG_NAME });
        adb_start.step.dependOn(&adb_install.step);
        run_step.dependOn(&adb_start.step);
    } else {
        const run_step = b.step("run", "Install and run the application on an Android device");
        const run = b.addRunArtifact(bin);
        run_step.dependOn(&run.step);
    }
}
