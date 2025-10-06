const sokol = @import("sokol");
const app_descriptor = @import("main.zig").app_descriptor;

export fn sokol_main() sokol.app.Desc {
    return app_descriptor;
}
