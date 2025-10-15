const std = @import("std");

pub const android = @import("android/android.zig");
pub const cpp = @import("cpp/cpp.zig");
pub const getEnvPath = @import("util.zig").getEnvPath;
pub const windows = @import("windows/windows.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xr_xml_path = b.option(
        std.Build.LazyPath,
        "path",
        "xr.xml path.",
    );

    const use_openxr_xml = b.option(
        OpenXrVersion,
        "version",
        "xr.xml from specification/registry/xr.xml in openxr-sdk version",
    );

    if (b.graph.host.result.os.tag == .windows) {
        if (windows.getVswhere(b.allocator)) |vswhere| {
            if (windows.getVcInstall(b.allocator, vswhere)) |vcinstall| {
                const bat = b.fmt("{s}/VC/Auxiliary/Build/vcvars64.bat", .{vcinstall});
                // std.log.debug("bat => {s}", .{bat});
                const run = b.addSystemCommand(&.{ "cmd.exe", "/c", bat, "&", "set" });

                const wf = b.addNamedWriteFiles("vcenv");
                _ = wf.addCopyFile(run.captureStdOut(), "vcenv");
            }
        }
    }

    {
        const xml = b.addModule("xml", .{
            .root_source_file = b.path("xml/xml.zig"),
            .target = target,
            .optimize = optimize,
        });

        const gen = b.addExecutable(.{
            .name = "xrgen",
            .root_module = b.addModule("xrgen", .{
                .root_source_file = b.path("xrgen/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{
                        .name = "xml",
                        .module = xml,
                    },
                },
                .link_libc = true,
            }),
        });
        b.installArtifact(gen);

        if (get_xml(b, xr_xml_path, use_openxr_xml)) |path| {
            const generate_cmd = b.addRunArtifact(gen);
            generate_cmd.addFileArg(path);
            const xr_zig_dir = generate_cmd.addOutputDirectoryArg("xr");
            const xr_module = b.addModule("xr", .{
                .root_source_file = xr_zig_dir.path(b, "xr.zig"),
            });
            b.modules.put("openxr", xr_module) catch @panic("OOM");

            // Also install xr.zig, if passed.
            const xr_zig_install_step = b.addInstallDirectory(.{
                .source_dir = xr_zig_dir,
                .install_dir = .{ .prefix = void{} },
                .install_subdir = "src/xr",
            });
            // xr_zig_install_step.step.dependOn(&generate_cmd.step);
            b.getInstallStep().dependOn(&xr_zig_install_step.step);
        }

        const xml_test = b.addTest(.{
            .root_module = xml,
        });
        const run_test = b.addRunArtifact(xml_test);
        b.step("test", "test").dependOn(&run_test.step);
    }
}

const OpenXrVersion = enum {
    @"1_0_26",
    @"1_0_27",
    @"1_0_34", // 1.0 last
    @"1_1_36", // 1.1 first
    @"1_1_52",
};

fn get_xml(
    b: *std.Build,
    maybe_xr_xml_path: ?std.Build.LazyPath,
    maybe_sdk_version: ?OpenXrVersion,
) ?std.Build.LazyPath {
    if (maybe_xr_xml_path) |xr_xml_path| {
        return xr_xml_path;
    }
    if (maybe_sdk_version) |sdk_version| {
        const openxr_dep = switch (sdk_version) {
            .@"1_0_26" => b.dependency("openxr_1_0_26", .{}),
            .@"1_0_27" => b.dependency("openxr_1_0_27", .{}),
            .@"1_0_34" => b.dependency("openxr_1_0_34", .{}),
            .@"1_1_36" => b.dependency("openxr_1_1_36", .{}),
            .@"1_1_52" => b.dependency("openxr_1_1_52", .{}),
        };
        return openxr_dep.path("specification/registry/xr.xml");
    }
    return null;
}
