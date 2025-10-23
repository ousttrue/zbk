const std = @import("std");
const windows = @import("../windows/windows.zig");
const CommandRunner = @import("../util.zig").CommandRunner;

pub const BuildType = union(enum) {
    Release,
};

pub const Options = struct {
    source: []const u8,
    args: []const []const u8 = &.{},
};

step: std.Build.Step,
// input
opts: Options,
vcenv: std.Build.LazyPath = undefined,
// output
output: std.Build.GeneratedFile = undefined,

pub fn create(b: *std.Build, opts: Options) *@This() {
    const this = b.allocator.create(@This()) catch @panic("OOM");
    this.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "NMakeStep",
            .owner = b,
            .makeFn = make,
        }),
        .opts = opts,
    };
    this.output = .{
        .step = &this.step,
    };

    {
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
    {
        const path3 = this.vcenv.getPath3(b, step);
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

        {
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
    }

    // manifest
    var man = step.owner.graph.cache.obtain();
    defer man.deinit();

    man.hash.addBytes(this.opts.source);
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

    if (try step.cacheHitAndWatch(&man)) {
        const digest = man.final();
        const prefix_dir = try b.cache_root.join(b.allocator, &.{ "o", &digest });
        this.output.path = prefix_dir;
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

    const prefix_dir = try b.cache_root.join(b.allocator, &.{ "o", &digest });
    this.output.path = prefix_dir;

    const nmake = "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/nmake.exe";

    var nmake_run = CommandRunner.init(b.allocator, &.{
        nmake,
    });
    defer nmake_run.deinit();

    if (this.opts.args.len > 0) {
        nmake_run.addArgs(this.opts.args);
    }

    try nmake_run.run(b, maybe_envmap, this.opts.source);

    try step.writeManifestAndWatch(&man);
}

pub fn getInstallPrefix(this: *@This()) std.Build.LazyPath {
    return .{ .generated = .{
        .file = &this.output,
    } };
}
