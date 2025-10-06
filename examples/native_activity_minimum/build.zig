const std = @import("std");
const zbk = @import("zbk");
const ndk = zbk.android.ndk;

const API_LEVEL = 35;

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .android,
    });
    const optimize = b.standardOptimizeOption(.{});

    const android_home = try zbk.getEnvPath(b.allocator, "ANDROID_HOME");
    const ndk_path = try ndk.getPath(b, .{ .android_home = android_home });
    const java_home = try zbk.getEnvPath(b.allocator, "JAVA_HOME");

    // build libmain.so
    const lib = b.addLibrary(.{
        .name = "main",
        .linkage = .dynamic,
        .root_module = b.addModule("main", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);
    // error: error: unable to provide libc for target 'aarch64-linux.5.10...6.16-android.29'
    const libc_file = try ndk.LibCFile.make(b, ndk_path, target, API_LEVEL);
    // for compile
    lib.addSystemIncludePath(.{ .cwd_relative = libc_file.include_dir });
    lib.addSystemIncludePath(.{ .cwd_relative = libc_file.sys_include_dir });
    // for link
    lib.setLibCFile(libc_file.path);
    lib.addLibraryPath(.{ .cwd_relative = libc_file.crt_dir });
    lib.linkSystemLibrary("android");
    lib.linkSystemLibrary("log");

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
        .artifact = lib,
        .android_manifest = b.path("AndroidManifest.xml"),
        .keystore_password = keystore_password,
        .keystore_file = keystore.output,
    });
    const install = b.addInstallFile(apk, "bin/hello.apk");
    b.getInstallStep().dependOn(&install.step);

    // adb install

    // adb run
}
