const std = @import("std");

pub const CmakeBuildType = union(enum) {
    Release,
};

pub const CmakeOptions = struct {
    source: std.Build.LazyPath,
    build_dir_name: []const u8,
    ndk_path: ?[]const u8 = null,
    dynamic: bool = true,
    build_type: CmakeBuildType = .Release,
};

pub const CmakeStep = struct {
    configure: *std.Build.Step.Run,
    build: *std.Build.Step.Run,
    install: *std.Build.Step.Run,
    prefix: *std.Build.Step.WriteFile,
};

pub fn build(b: *std.Build, opts: CmakeOptions) !CmakeStep {
    //
    // configure
    //
    const cmake_configure = b.addSystemCommand(&.{
        "cmake",
        "-G",
        "Ninja",
    });
    cmake_configure.setName("cmake configure");

    // -S
    cmake_configure.addArg("-S");
    cmake_configure.addDirectoryArg(opts.source);

    // -B
    cmake_configure.addArg("-B");
    const build_dir = cmake_configure.addOutputDirectoryArg(opts.build_dir_name);

    // --toolchain
    if (opts.ndk_path) |ndk_path| {

        // android ndk
        cmake_configure.addArgs(&.{
            "-DANDROID_ABI=arm64-v8a",
            "-DANDROID_PLATFORM=android-30",
            b.fmt("-DANDROID_NDK={s}", .{ndk_path}),
            b.fmt("-DCMAKE_TOOLCHAIN_FILE={s}/build/cmake/android.toolchain.cmake", .{ndk_path}),
        });
    }

    if (opts.dynamic) {
        cmake_configure.addArg("-DDYNAMIC_LOADER=ON");
    } else {
        cmake_configure.addArg("-DDYNAMIC_LOADER=OFF");
    }

    cmake_configure.addArgs(&.{
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.10",
        "-DCMAKE_POLICY_DEFAULT_CMP0148=OLD",
    });

    switch (opts.build_type) {
        .Release => {
            cmake_configure.addArg("-DCMAKE_BUILD_TYPE=Release");
        },
    }

    //
    // build
    //
    const cmake_build = b.addSystemCommand(&.{ "cmake", "--build" });
    cmake_build.setName("cmake build");
    cmake_build.addDirectoryArg(build_dir);
    cmake_build.step.dependOn(&cmake_configure.step);

    //
    // install
    //
    const cmake_install = b.addSystemCommand(&.{ "cmake", "--install" });
    cmake_install.setName("cmake install");
    cmake_install.addDirectoryArg(build_dir);
    cmake_install.step.dependOn(&cmake_build.step);

    // --prefix
    cmake_install.addArg("--prefix");
    const prefix_dir = cmake_install.addOutputDirectoryArg("prefix");

    const wf = b.addNamedWriteFiles("prefix");
    wf.step.dependOn(&cmake_install.step);
    _ = wf.addCopyDirectory(prefix_dir, "", .{});

    return CmakeStep{
        .configure = cmake_configure,
        .build = cmake_build,
        .install = cmake_install,
        .prefix = wf,
    };
}
