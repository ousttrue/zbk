const std = @import("std");
const windows = @import("../windows/windows.zig");
const CommandRunner = @import("../util.zig").CommandRunner;

pub const BuildType = union(enum) {
    Release,
};

pub const Options = struct {
    source: []const u8,
    // if multi target, should use different name for each target.
    build_dir_name: []const u8 = "build",
    ndk_path: ?[]const u8 = null,
    build_type: BuildType = .Release,
    use_vcenv: bool = false,
    args: []const []const u8 = &.{},
};

step: std.Build.Step,
// input
opts: Options,
vcenv: ?std.Build.LazyPath = null,
// output
output: std.Build.GeneratedFile = undefined,

pub fn create(b: *std.Build, opts: Options) *@This() {
    const this = b.allocator.create(@This()) catch @panic("OOM");
    this.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "CMakeStep",
            .owner = b,
            .makeFn = make,
        }),
        .opts = opts,
    };
    this.output = .{
        .step = &this.step,
    };

    if (opts.use_vcenv) {
        const vcenv = windows.GetVcEnv.create(b).captureStdOut();
        vcenv.addStepDependencies(&this.step);
        this.vcenv = vcenv;
    }

    return this;
}

fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    const this: *@This() = @fieldParentPtr("step", step);
    const b = step.owner;

    var maybe_envmap: ?*std.process.EnvMap = null;
    if (this.vcenv) |vcenv| {
        const path3 = vcenv.getPath3(b, step);
        var file = try b.cache_root.handle.openFile(path3.sub_path, .{});
        defer file.close();

        const output = try file.readToEndAlloc(b.allocator, std.math.maxInt(usize));
        defer b.allocator.free(output);

        const envmap = try b.allocator.create(std.process.EnvMap);
        maybe_envmap = envmap;
        envmap.* = .init(b.allocator);

        {
            // copy current
            var env = std.process.getEnvMap(b.allocator) catch @panic("OOM");
            defer env.deinit();
            var it = env.iterator();
            while (it.next()) |entry| {
                try envmap.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        var it = std.mem.splitSequence(u8, output, "\r\n");
        while (it.next()) |line| {
            if (std.mem.indexOf(u8, line, "=")) |pos| {
                const key = line[0..pos];
                const value = line[pos + 1 ..];
                if (windows.isVcenvContains(key)) {
                    try envmap.put(key, value);
                }
            }
        }
    }

    // manifest
    var man = step.owner.graph.cache.obtain();
    defer man.deinit();

    man.hash.addBytes(this.opts.source);
    man.hash.addBytes(@tagName(this.opts.build_type));
    for (this.opts.args) |arg| {
        man.hash.addBytes(arg);
    }
    if (maybe_envmap) |envmap| {
        // const path = vcenv.getPath3(b, step);
        // man.hash.addBytes(path.sub_path);
        var it = envmap.iterator();
        while (it.next()) |entry| {
            man.hash.addBytes(",");
            man.hash.addBytes(entry.key_ptr.*);
            man.hash.addBytes(":");
            man.hash.addBytes(entry.value_ptr.*);
        }
    }
    if (this.opts.ndk_path) |ndk_path| {
        man.hash.addBytes(ndk_path);
    }

    if (try step.cacheHitAndWatch(&man)) {
        const digest = man.final();
        this.output.path = try b.cache_root.join(b.allocator, &.{ "o", &digest });
        return;
    }

    const digest = man.final();
    const cache_dir = b.pathJoin(&.{ "o", &digest });
    b.cache_root.handle.makePath(cache_dir) catch |err| {
        return step.fail("unable to make path '{f}{s}': {s}", .{
            b.cache_root, cache_dir, @errorName(err),
        });
    };
    const cwd = b.fmt("{s}/o/{s}", .{ try b.cache_root.handle.realpathAlloc(b.allocator, ""), &digest });
    {
        var dir = try std.fs.openDirAbsolute(cwd, .{});
        defer dir.close();
    }

    this.output.path = try b.cache_root.join(b.allocator, &.{ "o", &digest });

    // const cmake = try b.findProgram(&.{"cmake"}, &.{});

    //
    // configure
    //
    var cmake_configure = CommandRunner.init(b.allocator, &.{
        "cmake",
        "-G",
        "Ninja",
        "-S",
        this.opts.source,
        "-B",
        "build",
        "-DCMAKE_INSTALL_PREFIX=prefix",
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.10",
        "-DCMAKE_POLICY_DEFAULT_CMP0148=OLD",
    });
    defer cmake_configure.deinit();

    // --toolchain
    if (this.opts.ndk_path) |ndk_path| {
        // android ndk
        cmake_configure.addArgs(&.{
            "-DANDROID_ABI=arm64-v8a",
            "-DANDROID_PLATFORM=android-30",
            b.fmt("-DANDROID_NDK={s}", .{ndk_path}),
            b.fmt("-DCMAKE_TOOLCHAIN_FILE={s}/build/cmake/android.toolchain.cmake", .{ndk_path}),
        });
    }

    switch (this.opts.build_type) {
        .Release => {
            cmake_configure.addArgs(&.{"-DCMAKE_BUILD_TYPE=Release"});
        },
    }

    if (this.opts.args.len > 0) {
        cmake_configure.addArgs(this.opts.args);
    }

    try cmake_configure.run(b, maybe_envmap, cwd);

    //
    // build
    //
    var cmake_build = CommandRunner.init(b.allocator, &.{
        "cmake",
        "--build",
        "build",
    });
    try cmake_build.run(b, maybe_envmap, cwd);

    //
    // install
    //
    var cmake_install = CommandRunner.init(b.allocator, &.{
        "cmake",
        "--install",
        "build",
    });
    try cmake_install.run(b, maybe_envmap, cwd);

    try step.writeManifestAndWatch(&man);
}

pub fn getBuild(this: *@This()) std.Build.LazyPath {
    const cache_dir = std.Build.LazyPath{ .generated = .{
        .file = &this.output,
    } };
    return cache_dir.path(this.step.owner, "build");
}

pub fn getInstallPrefix(this: *@This()) std.Build.LazyPath {
    const cache_dir = std.Build.LazyPath{ .generated = .{
        .file = &this.output,
    } };
    return cache_dir.path(this.step.owner, "prefix");
}
