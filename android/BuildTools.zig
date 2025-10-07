const std = @import("std");

path: []const u8,

pub fn init(b: *std.Build, android_home: []const u8) !@This() {
    return @This(){
        .path = try getBuildToolsPath(b, android_home),
    };
}

fn getBuildToolsPath(b: *std.Build, android_home: []const u8) ![]const u8 {
    var root = try std.fs.openDirAbsolute(android_home, .{});
    defer root.close();

    var build_tools_dir = try root.openDir("build-tools", .{ .iterate = true });
    defer build_tools_dir.close();

    var it = build_tools_dir.iterate();
    var version: []const u8 = "";
    while (try it.next()) |entry| {
        if (std.mem.order(
            u8,
            entry.name,
            version,
        ) == .gt) {
            version = entry.name;
        }
    }
    if (version.len == 0) {
        return error.no_build_tools;
    }

    return b.fmt("{s}/build-tools/{s}", .{ android_home, version });
}

pub const RunOutput = struct {
    run: *std.Build.Step.Run,
    output: std.Build.LazyPath,
};

pub fn aapt2_compile(
    self: @This(),
    b: *std.Build,
    resource: std.Build.LazyPath,
) RunOutput {
    const run = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.path, "aapt2.exe" }),
        "compile",
    });
    run.setName("aapt2 compile --dir");

    run.addArg("--dir");
    run.addDirectoryArg(resource);

    run.addArg("-o");
    const output = run.addOutputFileArg("resource_dir.flat.zip");

    return .{
        .run = run,
        .output = output,
    };
}

pub fn aapt2_link(
    self: @This(),
    b: *std.Build,
    root_jar: []const u8,
    android_manifest: std.Build.LazyPath,
    api_level: u8,
    resources_flat_zip: std.Build.LazyPath,
) RunOutput {
    const run = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.path, "aapt2.exe" }),
        "link",
        "-I", // add an existing package to base include set
        root_jar,
    });
    run.setName("aapt2 link");

    if (b.verbose) {
        run.addArg("-v");
        run.addArg("--debug-mode");
    }

    run.addArg("--manifest");
    run.addFileArg(android_manifest);

    run.addArgs(&[_][]const u8{
        "--target-sdk-version",
        b.fmt("{}", .{api_level}),
    });

    run.addArg("-o");
    const output = run.addOutputFileArg("resources.apk");

    run.addFileArg(resources_flat_zip);

    return .{
        .run = run,
        .output = output,
    };
}

// Align contents of .apk (zip)
pub fn zipalign(
    self: @This(),
    b: *std.Build,
    zip_file: std.Build.LazyPath,
) RunOutput {
    // If you use apksigner, zipalign must be used before the APK file has been signed.
    // If you sign your APK using apksigner and make further changes to the APK, its signature is invalidated.
    // Source: https://developer.android.com/tools/zipalign (10th Sept, 2024)
    //
    // Example: "zipalign -P 16 -f -v 4 infile.apk outfile.apk"
    var run = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.path, "zipalign.exe" }),
        "-P", // aligns uncompressed .so files to the specified page size in KiB...
        "16", // ... align to 16kb
        "-f", // overwrite existing files
        // "-z", // recompresses using Zopfli. (very very slow)
        "4",
    });
    run.setName("zipalign");

    if (b.verbose) {
        run.addArg("-v");
    }

    // Depend on zip file and the additional update to it
    run.addFileArg(zip_file);

    const output = run.addOutputFileArg("aligned.apk");

    return .{
        .run = run,
        .output = output,
    };
}

pub fn apksigner(
    self: @This(),
    b: *std.Build,
    keystore_file: std.Build.LazyPath,
    keystore_password: []const u8,
    aligned_apk_file: std.Build.LazyPath,
) RunOutput {
    const run = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.path, "apksigner.bat" }),
        "sign",
    });
    run.setName("apksigner");
    run.addArg("--ks"); // ks = keystore
    run.addFileArg(keystore_file);
    run.addArgs(&.{ "--ks-pass", b.fmt("pass:{s}", .{keystore_password}) });
    run.addArg("--out");
    const output = run.addOutputFileArg("signed-and-aligned-apk.apk");
    run.addFileArg(aligned_apk_file);
    return .{
        .run = run,
        .output = output,
    };
}
