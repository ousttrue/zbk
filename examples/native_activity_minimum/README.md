# native_activity_minimum

```zig
export fn ANativeActivity_onCreate(
    activity: *c.ANativeActivity,
    savedState: *anyopaque,
    savedStateSize: usize,
) void {
    _ = activity;
    _ = savedState;
    _ = savedStateSize;
    std.log.debug("ANativeActivity: onCreate !", .{});
}
```
