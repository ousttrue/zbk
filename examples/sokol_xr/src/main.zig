const std = @import("std");
const openxr = @import("openxr");

// in openxr_loader
pub extern fn xrGetInstanceProcAddr(
    instance: *anyopaque,
    procname: [*:0]const u8,
    function: *anyopaque,
) c_longlong;

fn printVersion() void {
    const V = extern union {
        value: u64,
        major_minor_patch: extern struct {
            patch: u32,
            minor: u16,
            major: u16,
        },
    };
    const v = V{ .value = openxr.core.CURRENT_API_VERSION };
    std.log.debug("{}.{}.{}", .{
        v.major_minor_patch.major,
        v.major_minor_patch.minor,
        v.major_minor_patch.patch,
    });
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.detectLeaks();
    // const allocator = gpa.allocator();

    printVersion();
    var create_info: xr.InstanceCreateInfo = .{
        .application_info = .{
            .application_version = 0,
            .application_name = [1]u8{0} ** xr.MAX_APPLICATION_NAME_SIZE,
            .engine_version = 0,
            .engine_name = [1]u8{0} ** xr.MAX_ENGINE_NAME_SIZE,
            .api_version = xr.CURRENT_API_VERSION,
        },
    };
    _ = try std.fmt.bufPrintZ(&create_info.application_info.application_name, "{s}", .{"openxr-zig-app"});
    _ = try std.fmt.bufPrintZ(&create_info.application_info.engine_name, "{s}", .{"openxr-zig-engine"});

    var instance: xr.Instance = undefined;
    var dispatcher: openxr.features.XR_VERSION_1_0 = undefined;
    try openxr.getProcs(
        xrGetInstanceProcAddr,
        &create_info,
        &instance,
        &dispatcher,
    );
    defer _ = dispatcher.xrDestroyInstance(instance);

}
