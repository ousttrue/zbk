const std = @import("std");
const SdkInfo = @import("SdkInfo.zig");

bin_path: []const u8,

pub fn init(b: *std.Build, info: SdkInfo) !@This() {
    switch (info.jdk_location) {
        .java_home => |java_home| {
            return @This(){
                .bin_path = try getJavaBinPath(b, java_home),
            };
        },
        .bin_path => |bin_path| {
            return @This(){
                .bin_path = bin_path,
            };
        },
    }
}

fn getJavaBinPath(b: *std.Build, java_home: []const u8) ![]const u8 {
    var root = try std.fs.openDirAbsolute(java_home, .{});
    defer root.close();

    var bin = try root.openDir("bin", .{});
    defer bin.close();

    return b.fmt("{s}/bin", .{java_home});
}

pub const RunOutput = struct {
    run: *std.Build.Step.Run,
    output: std.Build.LazyPath,
};

// Extract *.apk file created with "aapt2 link"
pub fn jar_extract(
    self: @This(),
    b: *std.Build,
    resources_apk: std.Build.LazyPath,
) *std.Build.Step.Run {
    const jar = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.bin_path, "jar" }),
    });
    jar.setName("jar --extract");
    if (b.verbose) {
        jar.addArg("--verbose");
    }

    jar.addArg("--extract");
    jar.addPrefixedFileArg("--file=", resources_apk);

    return jar;
}

// Create zip via "jar" as it's cross-platform and aapt2 can't zip *.so or *.dex files.
// - lib/**/*.so
// - classes.dex
// - {directory with all resource files like: AndroidManifest.xml, res/values/strings.xml}
pub fn jar_compress(
    self: @This(),
    b: *std.Build,
    apk_contents_dir: std.Build.LazyPath,
) RunOutput {
    const jar = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.bin_path, "jar" }),
    });
    jar.setName("jar compress");

    jar.setCwd(apk_contents_dir);
    // NOTE(jae): 2024-09-30
    // Hack to ensure this side-effect re-triggers zipping this up
    jar.addFileInput(apk_contents_dir.path(b, "AndroidManifest.xml"));

    // Written as-is from running "jar --help"
    // -c, --create      = Create the archive. When the archive file name specified
    // -u, --update      = Update an existing jar archive
    // -f, --file=FILE   = The archive file name. When omitted, either stdin or
    // -M, --no-manifest = Do not create a manifest file for the entries
    // -0, --no-compress = Store only; use no ZIP compression
    const compress_zip_arg = "-cfM";
    if (b.verbose) jar.addArg(compress_zip_arg ++ "v") else jar.addArg(compress_zip_arg);
    const output_zip_file = jar.addOutputFileArg("compiled_code.zip");
    jar.addArg(".");
    return .{
        .run = jar,
        .output = output_zip_file,
    };
}

pub fn jar_update(
    self: @This(),
    b: *std.Build,
    zip_file: std.Build.LazyPath,
    uncompressed: std.Build.LazyPath,
) *std.Build.Step {

    // Update zip with files that are not compressed (ie. resources.arsc)
    const jar = b.addSystemCommand(&.{
        b.pathResolve(&.{ self.bin_path, "jar" }),
    });
    jar.setName("jar update");
    jar.setCwd(uncompressed);
    jar.addFileInput(uncompressed.path(b, "resources.arsc"));

    // Written as-is from running "jar --help"
    // -c, --create      = Create the archive. When the archive file name specified
    // -u, --update      = Update an existing jar archive
    // -f, --file=FILE   = The archive file name. When omitted, either stdin or
    // -M, --no-manifest = Do not create a manifest file for the entries
    // -0, --no-compress = Store only; use no ZIP compression
    const update_zip_arg = "-ufM0";
    if (b.verbose) jar.addArg(update_zip_arg ++ "v") else jar.addArg(update_zip_arg);
    jar.addFileArg(zip_file);
    jar.addArg(".");

    return &jar.step;
}

pub const KeyStore = struct {
    const Algorithm = enum {
        rsa,

        /// arg returns the keytool argument
        fn arg(self: Algorithm) []const u8 {
            return switch (self) {
                .rsa => "RSA",
            };
        }
    };

    alias: []const u8 = "default",
    algorithm: Algorithm = .rsa,
    /// in bits, the maximum size of an RSA key supported by the Android keystore is 4096 bits (as of 2024)
    key_size_in_bits: u32 = 4096,
    validity_in_days: u32 = 10_000,
    /// https://stackoverflow.com/questions/3284055/what-should-i-use-for-distinguished-name-in-our-keystore-for-the-android-marke/3284135#3284135
    distinguished_name: []const u8 = "CN=example.com, OU=ID, O=Example, L=Doe, S=Jane, C=GB",

    pub fn make(
        self: @This(),
        b: *std.Build,
        java_bin_path: []const u8,
        password: []const u8,
    ) RunOutput {
        const keytool = b.addSystemCommand(&.{
            // https://docs.oracle.com/en/java/javase/17/docs/specs/man/keytool.html
            b.fmt("{s}/keytool", .{java_bin_path}),
            "-genkey",
            "-v",
        });
        keytool.setName("keytool");
        keytool.addArg("-keystore");
        const keystore_file = keytool.addOutputFileArg("zig-generated.keystore");
        keytool.addArgs(&.{
            // -alias "ca"
            "-alias",
            self.alias,
            // -keyalg "rsa"
            "-keyalg",
            self.algorithm.arg(),
            "-keysize",
            b.fmt("{d}", .{self.key_size_in_bits}),
            "-validity",
            b.fmt("{d}", .{self.validity_in_days}),
            "-storepass",
            password,
            "-keypass",
            password,
            // -dname "CN=example.com, OU=ID, O=Example, L=Doe, S=Jane, C=GB"
            "-dname",
            self.distinguished_name,
        });
        // ignore stderr, it just gives you an output like:
        // "Generating 4,096 bit RSA key pair and self-signed certificate (SHA384withRSA) with a validity of 10,000 days
        // for: CN=example.com, OU=ID, O=Example, L=Doe, ST=Jane, C=GB"
        _ = keytool.captureStdErr();

        return .{
            .output = keystore_file,
            .run = keytool,
        };
    }
};

pub fn makeKeystore(
    self: @This(),
    b: *std.Build,
    keystore_password: []const u8,
) RunOutput {
    const keystore = KeyStore{};
    return keystore.make(b, self.bin_path, keystore_password);
}
