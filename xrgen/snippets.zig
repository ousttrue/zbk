pub extern fn xrGetInstanceProcAddr(
    instance: *anyopaque,
    procname: [*:0]const u8,
    function: *anyopaque,
) i64;

pub fn getProcs(
    loader: anytype,
    instance: *anyopaque,
    table: anytype,
) void {
    inline for (std.meta.fields(@typeInfo(@TypeOf(table)).pointer.child)) |field| {
        const name: [*:0]const u8 = @ptrCast(field.name ++ "\x00");
        var cmd_ptr: xr.PFN_xrVoidFunction = undefined;
        const result = loader(instance, name, @ptrCast(&cmd_ptr));
        if (result != 0) @panic("loader");
        @field(table, field.name) = @ptrCast(cmd_ptr);
    }
}
