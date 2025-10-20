const std = @import("std");
const windows = @import("../windows/windows.zig");

pub const CmakeBuildType = union(enum) {
    Release,
};

pub const CmakeOptions = struct {
    source: std.Build.LazyPath,
    // if multi target, should use different name for each target.
    build_dir_name: []const u8 = "build",
    ndk_path: ?[]const u8 = null,
    build_type: CmakeBuildType = .Release,
    use_vcenv: bool = false,
    args: []const []const u8 = &.{},
};

pub const SetEnvFromVcenv = struct {
    step: std.Build.Step,
    /// run cmake
    run: *std.Build.Step.Run,
    /// captureStdout of vcvars64.bat
    vcenv: std.Build.LazyPath,

    pub fn create(
        owner: *std.Build,
        run: *std.Build.Step.Run,
        vcenv: std.Build.LazyPath,
    ) *@This() {
        const self = owner.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "SetEnvFromVcenv",
                .owner = owner,
                .makeFn = make,
            }),
            .run = run,
            .vcenv = vcenv,
        };

        // run step wait self
        run.step.dependOn(&self.step);
        // self wait vcenv
        vcenv.addStepDependencies(&self.step);

        return self;
    }

    const ENVS = [_][]const u8{
        "PATH",
        "INCLUDE",
        "LIB",
        "LIBPATH",
        "VCINSTALLDIR",
        "VSINSTALLDIR",
        "VCTOOLSINSTALLDIR",
        "VSCMD_VER",
    };

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;

        const abs_path = b.pathFromRoot(self.vcenv.getPath(b));

        var file = std.fs.openFileAbsolute(abs_path, .{}) catch |e| {
            if (e == error.FileNotFound) {
                std.log.debug("dependOn? FileNotFound: {s}", .{abs_path});
            }
            return e;
        };
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);

        const output = try reader.interface.allocRemaining(b.allocator, .unlimited);
        defer b.allocator.free(output);

        var it = std.mem.splitSequence(u8, output, "\r\n");
        while (it.next()) |line| {
            if (std.mem.indexOf(u8, line, "=")) |pos| {
                const key = line[0..pos];
                const value = line[pos + 1 ..];
                for (ENVS) |env| {
                    if (std.ascii.eqlIgnoreCase(env, key)) {
                        // std.log.debug("{s} => {s}", .{ key, value });
                        self.run.setEnvironmentVariable(key, value);
                        break;
                    }
                }
            }
        }
    }
};

pub const CmakeStep = struct {
    configure: *std.Build.Step.Run,
    build: *std.Build.Step.Run,
    install: *std.Build.Step.Run,
    prefix: *std.Build.Step.WriteFile,
};

fn getVcEnv(b: *std.Build) !std.Build.LazyPath {
    if (b.graph.host.result.os.tag != .windows) {
        return error.not_windows_host;
    }
    const vswhere = windows.getVswhere(b.allocator) orelse {
        return error.no_vswhere;
    };
    const vcinstall = windows.getVcInstall(b.allocator, vswhere) orelse {
        return error.no_vcinstall;
    };
    const bat = b.fmt("{s}/VC/Auxiliary/Build/vcvars64.bat", .{vcinstall});
    const run = b.addSystemCommand(&.{ "cmd.exe", "/c", bat, "&", "set" });
    return run.captureStdOut();
}

pub fn build(b: *std.Build, opts: CmakeOptions) CmakeStep {
    const maybe_vcenv: ?std.Build.LazyPath = if (opts.use_vcenv)
        getVcEnv(b) catch |e| {
            std.log.err("{s}", .{@errorName(e)});
            @panic("no vcenv");
        }
    else
        null;

    //
    // configure
    //
    const cmake_configure = b.addSystemCommand(&.{
        "cmake",
        "-G",
        "Ninja",
    });
    cmake_configure.setName("cmake configure");
    if (maybe_vcenv) |vcenv| {
        _ = SetEnvFromVcenv.create(b, cmake_configure, vcenv);
    }

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

    cmake_configure.addArgs(&.{
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.10",
        "-DCMAKE_POLICY_DEFAULT_CMP0148=OLD",
    });

    switch (opts.build_type) {
        .Release => {
            cmake_configure.addArg("-DCMAKE_BUILD_TYPE=Release");
        },
    }

    if (opts.args.len > 0) {
        cmake_configure.addArgs(opts.args);
    }

    const install_prefix = cmake_configure.addPrefixedOutputFileArg("-DCMAKE_INSTALL_PREFIX=", "prefix");

    //
    // build
    //
    const cmake_build = b.addSystemCommand(&.{ "cmake", "--build" });
    cmake_build.setName("cmake build");
    if (maybe_vcenv) |vcenv| {
        _ = SetEnvFromVcenv.create(b, cmake_build, vcenv);
    }
    cmake_build.addDirectoryArg(build_dir);
    // cmake_build.step.dependOn(&cmake_configure.step);

    //
    // install
    //
    const cmake_install = b.addSystemCommand(&.{ "cmake", "--install" });
    cmake_install.setName("cmake install");
    cmake_install.addDirectoryArg(build_dir);
    cmake_install.step.dependOn(&cmake_build.step);

    // --prefix
    cmake_install.addArg("--prefix");
    // const prefix_dir = cmake_install.addOutputDirectoryArg("prefix");
    cmake_install.addFileArg(install_prefix);

    const wf = b.addNamedWriteFiles("prefix");
    wf.step.dependOn(&cmake_install.step);
    _ = wf.addCopyDirectory(install_prefix, "", .{});

    return CmakeStep{
        .configure = cmake_configure,
        .build = cmake_build,
        .install = cmake_install,
        .prefix = wf,
    };
}
