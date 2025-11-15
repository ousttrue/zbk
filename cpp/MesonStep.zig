const std = @import("std");
const CommandRunner = @import("../util.zig").CommandRunner;

pub const BuildType = union(enum) {
    plain,
    debug,
    debugoptimized,
    release,
    minsize,
    custom,
};

pub const Options = struct {
    source: []const u8,
    // if multi target, should use different name for each target.
    build_dir_name: []const u8 = "build",
    build_type: BuildType = .release,
    // use_vcenv: bool = false,
    args: []const []const u8 = &.{},

    // /usr/bin/pkg-conf
    PKG_CONF: ?[]const u8 = null,
    // /usr/lib/pkgconfig
    PKG_CONFIG_PATH: ?[]const u8 = null,
};

step: std.Build.Step,
// input
opts: Options,
// output
output: std.Build.GeneratedFile = undefined,

pub fn create(b: *std.Build, opts: Options) *@This() {
    const this = b.allocator.create(@This()) catch @panic("OOM");
    this.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "MesonStep",
            .owner = b,
            .makeFn = make,
        }),
        .opts = opts,
    };
    this.output = .{
        .step = &this.step,
    };

    return this;
}

fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    const this: *@This() = @fieldParentPtr("step", step);
    const b = step.owner;

    // manifest
    var man = step.owner.graph.cache.obtain();
    defer man.deinit();

    man.hash.addBytes(this.opts.source);
    man.hash.addBytes(@tagName(this.opts.build_type));
    for (this.opts.args) |arg| {
        man.hash.addBytes(arg);
    }

    if (try step.cacheHitAndWatch(&man)) {
        const digest = man.final();
        const prefix_dir = try b.cache_root.join(b.allocator, &.{ "o", &digest, "prefix" });
        this.output.path = prefix_dir;
        return;
    }

    const digest = man.final();
    const cache_dir = b.pathJoin(&.{ "o", &digest });
    if (b.cache_root.handle.openDir(cache_dir, .{})) |dir| {
        try dir.deleteTree("build");
    } else |_| {
        //
    }
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

    const prefix_dir = try b.cache_root.join(b.allocator, &.{ "o", &digest, "prefix" });
    this.output.path = prefix_dir;

    const meson = try b.findProgram(&.{"meson"}, &.{});

    const envmap = try b.allocator.create(std.process.EnvMap); // = &b.graph.env_map;
    envmap.* = .init(b.allocator);
    {
        var it = b.graph.env_map.iterator();
        while (it.next()) |entry| {
            try envmap.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    if (this.opts.PKG_CONFIG_PATH) |pkg_config_path| {
        try envmap.put("PKG_CONFIG_PATH", pkg_config_path);
    }
    if (this.opts.PKG_CONF) |pkg_conf| {
        if (std.fs.path.dirname(pkg_conf)) |pkg_conf_bin| {
            const orig_path = envmap.get("PATH").?;
            try envmap.put("PATH", b.fmt("{s};{s}", .{ orig_path, pkg_conf_bin }));
        }
    }

    //
    // configure
    //
    var meson_setup = CommandRunner.init(b.allocator, &.{
        meson,
        "setup",
        "--prefix",
        b.fmt("{s}/prefix", .{cwd}),
    });
    defer meson_setup.deinit();

    meson_setup.addArgs(&.{ "--buildtype", @tagName(this.opts.build_type) });

    if (this.opts.args.len > 0) {
        meson_setup.addArgs(this.opts.args);
    }

    // last positional
    meson_setup.addArgs(&.{
        "build",
        // this.opts.source,
    });

    try meson_setup.run(b, envmap, this.opts.source);

    //
    // build
    //
    var meson_compile = CommandRunner.init(b.allocator, &.{
        meson,
        "compile",
        "-C",
        "build",
    });
    try meson_compile.run(b, envmap, this.opts.source);

    //
    // install
    //
    var meson_install = CommandRunner.init(b.allocator, &.{
        meson,
        "install",
        "-C",
        "build",
    });
    try meson_install.run(b, envmap, this.opts.source);

    try step.writeManifestAndWatch(&man);
}

pub fn getInstallPrefix(this: *@This()) std.Build.LazyPath {
    return .{ .generated = .{
        .file = &this.output,
    } };
}
