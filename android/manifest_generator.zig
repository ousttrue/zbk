const std = @import("std");

const ANDROID_MANIFEST_TEMPLATE_HEADER =
    \\<?xml version="1.0" encoding="utf-8" standalone="no"?>
    \\<manifest xmlns:tools="http://schemas.android.com/tools" xmlns:android="http://schemas.android.com/apk/res/android" package="{s}" android:versionCode="1">
;

const ANDROID_MANIFEST_TEMPLATE_BODY =
    \\<uses-sdk android:minSdkVersion="31" android:targetSdkVersion="{}" />
    \\<application android:debuggable="true" android:hasCode="false" android:label="{s}" tools:replace="android:icon,android:theme,android:allowBackup,label">
    \\<meta-data android:name="com.oculus.supportedDevices" android:value="quest2|questpro|quest3|quest3s"/>
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

pub const Permissions = enum {
    ///XR_META_boundary_visibility
    @"com.oculus.permission.BOUNDARY_VISIBILITY",
    /// TrackingEnvironment
    @"com.oculus.permission.ACCESS_TRACKING_ENV",
    /// Request permission to use Scene
    @"com.oculus.permission.USE_SCENE",
    /// Allow access to Spatial Anchors
    @"com.oculus.permission.USE_ANCHOR_API",
};

pub const Features = enum {
    @"android.hardware.vr.headtracking",
    @"com.oculus.software.body_tracking",
    @"com.oculus.feature.PASSTHROUGH",
    @"com.oculus.experimental.enabled",
};

pub const Feature = struct {
    type: Features,
    required: bool = false,
};

pub const ManifestOptions = struct {
    api_level: u8,
    pkg_name: []const u8,
    android_label: []const u8,
    features: []const Feature = &.{},
    permissions: []const Permissions = &.{},
    gles_version: ?[]const u8 = null,
};

pub fn generateAndroidManifest(
    b: *std.Build,
    opts: ManifestOptions,
) !std.Build.LazyPath {
    var w = std.Io.Writer.Allocating.init(b.allocator);
    try w.writer.print(ANDROID_MANIFEST_TEMPLATE_HEADER, .{
        opts.pkg_name,
    });

    if (opts.gles_version) |gles_version| {
        try w.writer.print(
            "<uses-feature android:glEsVersion=\"{s}\" android:required=\"true\" />\n",
            .{gles_version},
        );
    }

    for (opts.features) |feature| {
        if (feature.required) {
            try w.writer.print(
                "<uses-feature android:name=\"{s}\" android:required=\"true\" />\n",
                .{@tagName(feature.type)},
            );
        } else {
            try w.writer.print(
                "<uses-feature android:name=\"{s}\" />\n",
                .{@tagName(feature.type)},
            );
        }
    }

    for (opts.permissions) |permission| {
        try w.writer.print("<uses-permission android:name=\"{s}\" />\n", .{@tagName(permission)});
    }

    try w.writer.print(ANDROID_MANIFEST_TEMPLATE_BODY, .{
        opts.api_level,
        opts.android_label,
    });
    const content = try w.toOwnedSlice();
    const wf = b.addWriteFile("AndroidManifest.xml", content);
    return wf.getDirectory().path(b, "AndroidManifest.xml");
}
