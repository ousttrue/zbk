const std = @import("std");
const getEnvPath = @import("../util.zig").getEnvPath;

pub fn getVswhereFromEnv(allocator: std.mem.Allocator, env: []const u8) ![]const u8 {
    const program_files = try getEnvPath(allocator, env);
    const path = try std.fmt.allocPrint(
        allocator,
        "{s}/Microsoft Visual Studio/Installer/vswhere.exe",
        .{program_files},
    );
    try std.fs.accessAbsolute(path, .{});
    return path;
}

pub fn getVswhere(allocator: std.mem.Allocator) ![]const u8 {
    if (getVswhereFromEnv(allocator, "ProgramFiles(x86)")) |vswhere| {
        return vswhere;
    } else |_| {}
    if (getVswhereFromEnv(allocator, "ProgramFiles")) |vswhere| {
        return vswhere;
    } else |_| {}
    return error.vswhere_not_found;
}

pub const PrintLazyPath = struct {
    step: std.Build.Step,
    path: std.Build.LazyPath,

    pub fn create(owner: *std.Build, path: std.Build.LazyPath) *@This() {
        const self = owner.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "PrintLazyPath",
                .owner = owner,
                .makeFn = make,
            }),
            .path = path,
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;
        const path3 = self.path.getPath3(b, step);
        const path = try path3.toString(b.allocator);
        std.log.debug("pathFromRoot => {s}", .{b.pathFromRoot(path)});
    }
};

fn getLazyPathContent(b: *std.Build, path: std.Build.LazyPath) ![]const u8 {
    const path_str = b.pathFromRoot(path.getPath(b));

    var file = std.fs.openFileAbsolute(path_str, .{ .mode = .read_only }) catch |e| {
        std.log.err("openFileAbsolute => {s}", .{@errorName(e)});
        return error.openFileAbsolute;
    };
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var reader = file.reader(&buffer);

    return try reader.interface.allocRemaining(b.allocator, .unlimited);
}

pub const PrintLazyPathContent = struct {
    step: std.Build.Step,
    path: std.Build.LazyPath,

    pub fn create(owner: *std.Build, path: std.Build.LazyPath) *@This() {
        const self = owner.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "PrintLazyPath",
                .owner = owner,
                .makeFn = make,
            }),
            .path = path,
        };
        path.addStepDependencies(&self.step);
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *@This() = @fieldParentPtr("step", step);
        const content = try getLazyPathContent(step.owner, self.path);
        std.log.debug("content: {s}", .{content});
    }
};

pub const SelectResult = struct {
    step: std.Build.Step,
    substeps: std.array_list.Managed(std.Build.LazyPath),
    result: *std.Build.GeneratedFile,

    pub fn create(owner: *std.Build) *@This() {
        const self = owner.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "SelectResult",
                .owner = owner,
                .makeFn = make,
            }),
            .substeps = std.array_list.Managed(std.Build.LazyPath).init(owner.allocator),
            .result = owner.allocator.create(std.Build.GeneratedFile) catch @panic("OOM"),
        };
        self.result.step = &self.step;
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;
        for (self.substeps.items) |output| {
            if (getLazyPathContent(b, output)) |content| {
                if (content.len > 0) {
                    const trim = std.mem.trimEnd(u8, content, "\r\n");
                    self.result.path = trim;
                    break;
                }
            } else |_| {}
        }
    }

    pub fn addSubStep(self: *@This(), run: *std.Build.Step.Run) void {
        self.step.dependOn(&run.step);
        const output = run.captureStdOut();
        // output.addStepDependencies(&self.step);
        self.substeps.append(output) catch @panic("OOM");
    }

    pub fn getResult(self: @This()) std.Build.LazyPath {
        return .{ .generated = .{ .file = self.result } };
    }
};

fn system(allocator: std.mem.Allocator, argv: []const []const u8) ?[]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.spawn() catch @panic("OOM");
    child.waitForSpawn() catch @panic("OOM");
    var output: ?[]const u8 = null;
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
    _ = child.wait() catch @panic("OOM");
    return output;
}

fn getVcInstall(allocator: std.mem.Allocator, vswhere: []const u8) ![]const u8 {
    if (system(allocator, &.{
        vswhere,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualStudio.Product.BuildTools",
        "-property",
        "installationPath",
    })) |output| {
        return output;
    }

    if (system(allocator, &.{
        vswhere,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualStudio.Product.Community",
        "-property",
        "installationPath",
    })) |output| {
        return output;
    }

    if (system(allocator, &.{
        vswhere,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-property",
        "installationPath",
    })) |output| {
        return output;
    }

    return error.vc_not_found;
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

pub const VcEnv = struct {
    // output: []const u8,
    envmap: *std.process.EnvMap,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const vswhere = try getVswhere(arena.allocator());
        std.log.debug("vswhere => {s}", .{vswhere});

        const vcinstall = try getVcInstall(arena.allocator(), vswhere);
        const bat = try std.fmt.allocPrint(arena.allocator(), "{s}/VC/Auxiliary/Build/vcvars64.bat", .{vcinstall});
        std.log.debug("bat => {s}", .{bat});

        const output = system(arena.allocator(), &.{
            "cmd.exe",
            "/c",
            bat,
            "&",
            "set",
        }) orelse {
            return error.no_out_put;
        };
        // std.log.debug("{s}", .{output});

        const self = @This(){
            // .output = try allocator.dupe(u8, output),
            .envmap = try allocator.create(std.process.EnvMap),
        };
        self.envmap.* = .init(allocator);
        var it = std.mem.splitScalar(u8, output, '\n');
        while (it.next()) |line| {
            if (std.mem.indexOf(u8, line, "=")) |pos| {
                const key = line[0..pos];
                const value = line[pos + 1 ..];
                for (ENVS) |env| {
                    if (std.ascii.eqlIgnoreCase(env, key)) {
                        // std.log.debug("env: {s} => {s}", .{key, value});
                        var current = try arena.allocator().dupe(u8, value);
                        while (std.mem.indexOf(u8, current, "\\\\")) |found| {
                            current = try std.fmt.allocPrint(
                                arena.allocator(),
                                "{s}{s}",
                                .{ current[0..found], current[found + 1 ..] },
                            );
                        }
                        try self.envmap.put(key, try allocator.dupe(u8, std.mem.trimEnd(u8, current, "\r\n")));
                        break;
                    }
                }
            }
        }
        return self;
    }
};
