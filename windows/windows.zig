const std = @import("std");
const getEnvPath = @import("../util.zig").getEnvPath;

pub fn getVswhere(b: *std.Build) ?[]const u8 {
    var env = std.process.getEnvMap(b.allocator) catch @panic("OOM");
    defer env.deinit();
    if (env.get("ProgramFiles(x86)")) |program_files| {
        if (b.findProgram(&.{"vswhere"}, &.{b.fmt(
            "{s}/Microsoft Visual Studio/Installer",
            .{program_files},
        )})) |vswhere| {
            return vswhere;
        } else |_| {
            // error.FileNotFound
        }
    }
    if (env.get("ProgramFiles")) |program_files| {
        if (b.findProgram(&.{"vswhere"}, &.{b.fmt(
            "{s}/Microsoft Visual Studio/Installer",
            .{program_files},
        )})) |vswhere| {
            return vswhere;
        } else |_| {
            // error.FileNotFound
        }
    }
    return null;
}

const FindVcInstall = struct {
    step: std.Build.Step,
    output: std.Build.GeneratedFile = undefined,

    pub fn create(b: *std.Build) *@This() {
        const this = b.allocator.create(@This()) catch @panic("OOM");
        this.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "FindVcInstall",
                .owner = b,
                .makeFn = make,
            }),
        };
        this.output = .{
            .step = &this.step,
        };
        return this;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const this: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;
        const vswhere = getVswhere(b) orelse @panic("no vswhere");
        const vcinstall = getVcInstall(b.allocator, vswhere) orelse @panic("no vcinstall");
        this.output.path = b.fmt("{s}/VC/Auxiliary/Build/vcvars64.bat", .{vcinstall});
    }

    pub fn getVcVarsBat(this: *@This()) std.Build.LazyPath {
        return .{ .generated = .{
            .file = &this.output,
        } };
    }
};

pub const GetVcEnv = struct {
    step: std.Build.Step,
    input: std.Build.LazyPath,
    output: std.Build.GeneratedFile = undefined,

    pub fn create(b: *std.Build) *@This() {
        const vc_install = FindVcInstall.create(b);

        const this = b.allocator.create(@This()) catch @panic("OOM");
        this.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "GetVcEnv",
                .owner = b,
                .makeFn = make,
            }),
            .input = vc_install.getVcVarsBat(),
        };

        this.output = .{
            .step = &this.step,
        };
        vc_install.getVcVarsBat().addStepDependencies(&this.step);

        return this;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const this: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;

        // manifest
        var man = step.owner.graph.cache.obtain();
        defer man.deinit();

        const source_path = this.input.getPath3(b, step);
        _ = try man.addFilePath(source_path, null);

        if (try step.cacheHitAndWatch(&man)) {
            const digest = man.final();
            const cache_file = try b.cache_root.join(b.allocator, &.{ "o", &digest, "output" });
            this.output.path = cache_file;
            return;
        }

        const digest = man.final();
        const cache_file = try b.cache_root.join(b.allocator, &.{ "o", &digest, "output" });
        this.output.path = cache_file;
        const cache_dir = try b.cache_root.join(b.allocator, &.{ "o", &digest });
        b.cache_root.handle.makePath(cache_dir) catch |err| {
            return step.fail("unable to make path '{f}{s}': {s}", .{
                b.cache_root, cache_dir, @errorName(err),
            });
        };

        const path3 = this.input.getPath3(b, step);
        const path = try path3.toString(b.allocator);
        const fullpath = b.pathFromRoot(path);

        var res: u8 = undefined;
        const run = try b.runAllowFail(&.{
            "cmd.exe",
            "/c",
            fullpath,
            "&",
            "set",
        }, &res, .Ignore);

        var file = try b.cache_root.handle.createFile(cache_file, .{});
        defer file.close();
        try file.writeAll(run);

        try step.writeManifestAndWatch(&man);
    }

    pub fn captureStdOut(this: *@This()) std.Build.LazyPath {
        return .{ .generated = .{ .file = &this.output } };
    }
};

// pub const SelectResult = struct {
//     step: std.Build.Step,
//     substeps: std.array_list.Managed(std.Build.LazyPath),
//     result: *std.Build.GeneratedFile,
//
//     pub fn create(owner: *std.Build) *@This() {
//         const self = owner.allocator.create(@This()) catch @panic("OOM");
//         self.* = .{
//             .step = std.Build.Step.init(.{
//                 .id = .custom,
//                 .name = "SelectResult",
//                 .owner = owner,
//                 .makeFn = make,
//             }),
//             .substeps = std.array_list.Managed(std.Build.LazyPath).init(owner.allocator),
//             .result = owner.allocator.create(std.Build.GeneratedFile) catch @panic("OOM"),
//         };
//         self.result.step = &self.step;
//         return self;
//     }
//
//     fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
//         const self: *@This() = @fieldParentPtr("step", step);
//         const b = step.owner;
//         for (self.substeps.items) |output| {
//             if (getLazyPathContent(b, output)) |content| {
//                 if (content.len > 0) {
//                     const trim = std.mem.trimEnd(u8, content, "\r\n");
//                     self.result.path = trim;
//                     break;
//                 }
//             } else |_| {}
//         }
//     }
//
//     pub fn addSubStep(self: *@This(), run: *std.Build.Step.Run) void {
//         self.step.dependOn(&run.step);
//         const output = run.captureStdOut();
//         // output.addStepDependencies(&self.step);
//         self.substeps.append(output) catch @panic("OOM");
//     }
//
//     pub fn getResult(self: @This()) std.Build.LazyPath {
//         return .{ .generated = .{ .file = self.result } };
//     }
// };

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

pub fn getVcInstall(allocator: std.mem.Allocator, vswhere: []const u8) ?[]const u8 {
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

    return null;
}

// const ENVS = [_][]const u8{
//     "PATH",
//     "INCLUDE",
//     "LIB",
//     "LIBPATH",
//     "VCINSTALLDIR",
//     "VSINSTALLDIR",
//     "VCTOOLSINSTALLDIR",
//     "VSCMD_VER",
// };
//
// pub const VcEnv = struct {
//     // output: []const u8,
//     envmap: *std.process.EnvMap,
//
//     pub fn init(allocator: std.mem.Allocator) !@This() {
//         var arena = std.heap.ArenaAllocator.init(allocator);
//         defer arena.deinit();
//
//         const vswhere = getVswhere(arena.allocator()) orelse {
//             return error.no_vswhere;
//         };
//         std.log.debug("vswhere => {s}", .{vswhere});
//
//         const vcinstall = try getVcInstall(arena.allocator(), vswhere);
//         const bat = try std.fmt.allocPrint(arena.allocator(), "{s}/VC/Auxiliary/Build/vcvars64.bat", .{vcinstall});
//         std.log.debug("bat => {s}", .{bat});
//
//         const output = system(arena.allocator(), &.{
//             "cmd.exe",
//             "/c",
//             bat,
//             "&",
//             "set",
//         }) orelse {
//             return error.no_out_put;
//         };
//         // std.log.debug("{s}", .{output});
//
//         const self = @This(){
//             // .output = try allocator.dupe(u8, output),
//             .envmap = try allocator.create(std.process.EnvMap),
//         };
//         self.envmap.* = .init(allocator);
//         var it = std.mem.splitScalar(u8, output, '\n');
//         while (it.next()) |line| {
//             if (std.mem.indexOf(u8, line, "=")) |pos| {
//                 const key = line[0..pos];
//                 const value = line[pos + 1 ..];
//                 for (ENVS) |env| {
//                     if (std.ascii.eqlIgnoreCase(env, key)) {
//                         // std.log.debug("env: {s} => {s}", .{key, value});
//                         var current = try arena.allocator().dupe(u8, value);
//                         while (std.mem.indexOf(u8, current, "\\\\")) |found| {
//                             current = try std.fmt.allocPrint(
//                                 arena.allocator(),
//                                 "{s}{s}",
//                                 .{ current[0..found], current[found + 1 ..] },
//                             );
//                         }
//                         try self.envmap.put(key, try allocator.dupe(u8, std.mem.trimEnd(u8, current, "\r\n")));
//                         break;
//                     }
//                 }
//             }
//         }
//         return self;
//     }
// };
