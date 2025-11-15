const std = @import("std");
const BuildTools = @import("BuildTools.zig");
const PlatformTools = @import("PlatformTools.zig");
const Jdk = @import("Jdk.zig");

jdk: Jdk,
build_tools: BuildTools,
platform_tools: PlatformTools,
api_level: u8,
root_jar: []const u8,

pub const ApkBuilderOpts = struct {
    android_home: []const u8,
    java_home: []const u8,
    api_level: u8,
};

pub fn init(
    b: *std.Build,
    opts: ApkBuilderOpts,
) !@This() {
    const root_jar = b.pathResolve(&[_][]const u8{
        opts.android_home,
        "platforms",
        b.fmt("android-{}", .{opts.api_level}),
        "android.jar",
    });

    return @This(){
        .jdk = try Jdk.init(b, opts.java_home),
        .build_tools = try BuildTools.init(b, opts.android_home),
        .platform_tools = try PlatformTools.init(b, opts.android_home),
        .api_level = opts.api_level,
        .root_jar = root_jar,
    };
}

pub const Copy = struct {
    src: std.Build.LazyPath,
    dst: []const u8 = "lib/arm64-v8a/libmain.so",
};

pub const ApkOpts = struct {
    android_manifest: std.Build.LazyPath,
    keystore_file: std.Build.LazyPath,
    keystore_password: []const u8,
    resource_dir: std.Build.LazyPath,
    copy_list: []const Copy,
};

pub fn makeApk(self: @This(), b: *std.Build, opts: ApkOpts) std.Build.LazyPath {
    //
    // apk contents
    //
    // AndroidManifest.xml
    // TODO: classes.dex
    // lib/arm64-v8a/libmain.so
    // res
    //
    const aapt2_compile = self.build_tools.aapt2_compile(
        b,
        opts.resource_dir,
    );

    const aapt2_link = self.build_tools.aapt2_link(
        b,
        self.root_jar,
        opts.android_manifest,
        self.api_level,
        aapt2_compile.output,
    );

    const jar_extract = self.jdk.jar_extract(
        b,
        aapt2_link.output,
    );
    const tmp = b.addWriteFiles();
    tmp.step.name = "tmp";
    jar_extract.setCwd(tmp.getDirectory());

    const extracted = b.addWriteFiles();
    _ = extracted.addCopyDirectory(tmp.getDirectory(), "", .{});
    extracted.step.dependOn(&jar_extract.step);

    const apk_contents = b.addWriteFiles();
    apk_contents.step.name = "apk contents";
    apk_contents.step.dependOn(&jar_extract.step);
    _ = apk_contents.addCopyDirectory(
        extracted.getDirectory(),
        "",
        .{ .exclude_extensions = &.{"arsc"} },
    );

    for (opts.copy_list) |copy| {
        _ = apk_contents.addCopyFile(
            copy.src,
            copy.dst,
        );
    }

    const uncompressed = b.addWriteFiles();
    uncompressed.step.name = "uncompressed";
    uncompressed.step.dependOn(&jar_extract.step);
    _ = uncompressed.addCopyFile(extracted.getDirectory().path(b, "resources.arsc"), "resources.arsc");

    //
    // make apk
    //
    const jar_compress = self.jdk.jar_compress(
        b,
        apk_contents.getDirectory(),
    );
    jar_compress.run.step.dependOn(&apk_contents.step);
    const jar_update = self.jdk.jar_update(
        b,
        jar_compress.output,
        uncompressed.getDirectory(),
    );
    jar_update.dependOn(&jar_compress.run.step);
    jar_update.dependOn(&uncompressed.step);
    const zipalign = self.build_tools.zipalign(
        b,
        jar_compress.output,
    );
    zipalign.run.step.dependOn(jar_update);

    const apksigner = self.build_tools.apksigner(
        b,
        opts.keystore_file,
        opts.keystore_password,
        zipalign.output,
    );
    return apksigner.output;
}
