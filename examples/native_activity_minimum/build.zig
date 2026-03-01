const std = @import("std");
const zbk = @import("zbk");

const API_LEVEL = 35;
const PKG_NAME = "org.zbk.hello";

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .android,
    });
    const optimize = b.standardOptimizeOption(.{});

    const sdk_info = try zbk.android.SdkInfo.init(b.allocator, if (target.result.os.tag == .windows) .androidstudio else .opt);

    // build libmain.so
    const lib = b.addLibrary(.{
        .name = "zbk_hello",
        .linkage = .dynamic,
        .root_module = b.addModule("zbk_hello", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);
    // error: error: unable to provide libc for target 'aarch64-linux.5.10...6.16-android.29'
    const libc_file = try zbk.android.ndk.LibCFile.make(b, sdk_info.ndk_path, target, API_LEVEL);
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
        .sdk_info = sdk_info,
        .api_level = API_LEVEL,
    });

    const keystore_password = "example_password";
    const keystore = apk_builder.jdk.makeKeystore(b, keystore_password);

    // make apk from
    const apk = apk_builder.makeApk(b, .{
        .android_manifest = try zbk.android.generateAndroidManifest(b, .{
            .pkg_name = PKG_NAME,
            .api_level = API_LEVEL,
            .android_label = lib.name,
        }),
        .resource_dir = b.path("res"),
        .keystore_password = keystore_password,
        .keystore_file = keystore.output,
        .copy_list = &.{
            .{ .src = lib.getEmittedBin() },
        },
    });
    const install = b.addInstallFile(apk, "bin/hello.apk");
    b.getInstallStep().dependOn(&install.step);

    // adb install
    // adb run
    const run_step = b.step("run", "Install and run the application on an Android device");
    const adb_install = apk_builder.platform_tools.adb_install(b, install.source);
    const adb_start = apk_builder.platform_tools.adb_start(b, .{ .package_name = PKG_NAME });
    adb_start.step.dependOn(&adb_install.step);
    run_step.dependOn(&adb_start.step);
}
