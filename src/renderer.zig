const Camera = @import("camera.zig");
const glfw = @import("glfw");

pub const globals = struct {
    pub var camera: Camera = .{};
    pub var window: glfw.Window = undefined;
};

pub fn init() void {}
