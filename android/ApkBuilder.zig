const std = @import("std");
const BuildTools = @import("BuildTools.zig");
const Jdk = @import("Jdk.zig");

jdk: Jdk,
build_tools: BuildTools,
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
        .api_level = opts.api_level,
        .root_jar = root_jar,
    };
}

pub const ApkOpts = struct {
    android_manifest: std.Build.LazyPath,
    artifact: *std.Build.Step.Compile,
    keystore_file: std.Build.LazyPath,
    keystore_password: []const u8,
    resource_dir: std.Build.LazyPath,
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
    _ = apk_contents.addCopyFile(
        opts.artifact.getEmittedBin(),
        // b.fmt("lib/arm64-v8a/lib{s}.so", .{opts.artifact.name}),
        "lib/arm64-v8a/libmain.so",
    );

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

const ANDROID_MANIFEST_TEMPLATE_HEADER =
    \\<?xml version="1.0" encoding="utf-8" standalone="no"?>
    \\<manifest xmlns:tools="http://schemas.android.com/tools" xmlns:android="http://schemas.android.com/apk/res/android" package="{s}" android:versionCode="1">
;
const ANDROID_MANIFEST_TEMPLATE_BODY =
    \\<uses-sdk android:minSdkVersion="31" android:targetSdkVersion="{}" />
    \\<application android:debuggable="true" android:hasCode="false" android:label="{s}" tools:replace="android:icon,android:theme,android:allowBackup,label">
    \\<activity android:configChanges="keyboardHidden|orientation" android:name="android.app.NativeActivity" android:exported="true">
    \\<meta-data android:name="android.app.lib_name" android:value="main"/>
    \\<intent-filter>
    \\<action android:name="android.intent.action.MAIN"/>
    \\<category android:name="android.intent.category.LAUNCHER"/>
    \\</intent-filter>
    \\</activity>
    \\</application>
    \\</manifest>
;

pub fn generateAndroidManifest(
    self: @This(),
    b: *std.Build,
    pkgname: []const u8,
    label: []const u8,
) ![]const u8 {
    var w = std.Io.Writer.Allocating.init(b.allocator);
    try w.writer.print(ANDROID_MANIFEST_TEMPLATE_HEADER, .{pkgname});
    // for (config.permissions.items) |perm| {
    //     try w.writer.print("<uses-permission android:name=\"{s}\"/>\n", .{perm});
    // }
    try w.writer.print(ANDROID_MANIFEST_TEMPLATE_BODY, .{
        self.api_level,
        label,
    });
    return try w.toOwnedSlice();
}
