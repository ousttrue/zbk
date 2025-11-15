const std = @import("std");

//
// sdk
//
const OpenXrVersion = enum {
    @"1_0_26",
    @"1_0_27",
    @"1_0_34", // 1.0 last
    @"1_1_36", // 1.1 first
    @"1_1_52",
};

fn getXrSdkpath(b: *std.Build) ?std.Build.LazyPath {
    const maybe_openxr = b.option(
        std.Build.LazyPath,
        "openxr",
        "openxr-sdk path",
    );
    if (maybe_openxr) |openxr| {
        return openxr;
    }

    const maybe_openxr_version = b.option(
        OpenXrVersion,
        "version",
        "xr.xml from specification/registry/xr.xml in openxr-sdk version",
    );
    if (maybe_openxr_version) |openxr_version| {
        const openxr_dep = switch (openxr_version) {
            .@"1_0_26" => b.dependency("openxr_1_0_26", .{}),
            .@"1_0_27" => b.dependency("openxr_1_0_27", .{}),
            .@"1_0_34" => b.dependency("openxr_1_0_34", .{}),
            .@"1_1_36" => b.dependency("openxr_1_1_36", .{}),
            .@"1_1_52" => b.dependency("openxr_1_1_52", .{}),
        };
        return openxr_dep.path("");
    }

    return null;
}

//
// build
//
pub fn build_xrgen(
    b: *std.Build,
) void {
    const host_target = b.graph.host;
    const host_optimize = std.builtin.OptimizeMode.ReleaseSafe;

    const xml = b.addModule("xml", .{
        .root_source_file = b.path("xml/xml.zig"),
        .target = host_target,
        .optimize = host_optimize,
    });

    const gen = b.addExecutable(.{
        .name = "xr_gen",
        .root_module = b.addModule("xrgen", .{
            .root_source_file = b.path("xrgen/main.zig"),
            .target = host_target,
            .optimize = host_optimize,
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

    const xml_test = b.addTest(.{
        .root_module = xml,
    });
    const run_test = b.addRunArtifact(xml_test);
    b.step("test", "test").dependOn(&run_test.step);

    if (getXrSdkpath(b)) |openxr_sdk| {
        // run xrgen
        const xr_xml = openxr_sdk.path(b, "specification/registry/xr.xml");
        const xr_zig_dir = runXrGen(b, gen, xr_xml);
        const xr_wf = b.addNamedWriteFiles("openxr");
        _ = xr_wf.addCopyDirectory(xr_zig_dir, "", .{});
    }
}

fn runXrGen(
    b: *std.Build,
    gen: *std.Build.Step.Compile,
    xr_xml: std.Build.LazyPath,
) std.Build.LazyPath {
    const generate_cmd = b.addRunArtifact(gen);
    generate_cmd.addFileArg(xr_xml);
    return generate_cmd.addOutputDirectoryArg("xr");
}
