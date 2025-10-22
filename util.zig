const std = @import("std");

pub fn getEnvPath(allocator: std.mem.Allocator, env_name: []const u8) ?[]const u8 {
    var env = std.process.getEnvMap(allocator) catch @panic("OOM");
    defer env.deinit();

    const env_value = env.get(env_name) orelse {
        return null;
    };
    const env_path = allocator.dupe(u8, env_value) catch @panic("OOM");

    for (env_path) |*ch| {
        if (ch.* == '\\') {
            ch.* = '/';
        }
    }
    return env_path;
}

pub const SystemOpts = struct {
    envmap: ?*std.process.EnvMap = null,
    cwd: ?[]const u8 = null,
    stdout: std.process.Child.StdIo = .Inherit,
};

pub fn system(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    opts: SystemOpts,
) ?[]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = opts.stdout;
    child.env_map = opts.envmap;
    child.cwd = opts.cwd;

    child.spawn() catch @panic("OOM");
    child.waitForSpawn() catch @panic("OOM");
    var output: ?[]const u8 = null;
    if (child.stdout_behavior == .Pipe) {
        if (child.stdout) |stdout| {
            var stdout_reader = stdout.readerStreaming(&.{});
            const o = stdout_reader.interface.allocRemaining(allocator, .unlimited) catch |e| @panic(@errorName(e));
            const trimed = std.mem.trimEnd(u8, o, "\r\n");
            if (trimed.len > 0) {
                output = trimed;
            }
        } else {
            @panic("no stdout");
        }
    }
    _ = child.wait() catch @panic("OOM");
    return output;
}

pub const PrintLazyPath = struct {
    step: std.Build.Step,
    path: std.Build.LazyPath,

    pub fn create(owner: *std.Build, path: std.Build.LazyPath) *@This() {
        const this = owner.allocator.create(@This()) catch @panic("OOM");
        this.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "PrintLazyPath",
                .owner = owner,
                .makeFn = make,
            }),
            .path = path,
        };
        return this;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const this: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;
        const path3 = this.path.getPath3(b, step);
        const path = try path3.toString(b.allocator);
        std.log.debug("PrintLazyPath => {s}", .{b.pathFromRoot(path)});
    }
};

pub const PrintLazyPathContent = struct {
    step: std.Build.Step,
    path: std.Build.LazyPath,

    pub fn create(owner: *std.Build, path: std.Build.LazyPath) *@This() {
        const this = owner.allocator.create(@This()) catch @panic("OOM");
        this.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "PrintLazyPath",
                .owner = owner,
                .makeFn = make,
            }),
            .path = path,
        };
        path.addStepDependencies(&this.step);
        return this;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const this: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;

        const path3 = this.path.getPath3(b, step);
        const file = try b.cache_root.handle.openFile(path3.sub_path, .{});
        defer file.close();
        const content = try file.readToEndAlloc(b.allocator, std.math.maxInt(usize));
        std.log.debug("content: {s}", .{content});
    }
};
