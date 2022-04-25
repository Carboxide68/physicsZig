const common = @import("common.zig");
const std = @import("std");
const vector = @import("vector.zig");
const glfw = @import("glfw");
const Mat3 = vector.Mat3;
const Vec3 = vector.Vec3;
const Vec2 = vector.Vec2;

const Camera = @This();

camera_matrix: Mat3 = Mat3.init(1),
view_matrix: Mat3 = Mat3.init(1),

pub fn init() Camera {

    var camera = Camera{};
    camera.updateCameraMatrix();

    return camera;
}

pub fn getAssembled(self: Camera) Mat3 {
    return Mat3.mMult(self.camera_matrix, self.view_matrix);
}

pub fn updateCameraMatrix(self: *Camera) void {
    const window_size = common.window.getFramebufferSize() catch return;
    const width = @intToFloat(f32, window_size.width);
    const height = @intToFloat(f32, window_size.height);
    const bigger = @maximum(width, height);
    self.camera_matrix = .{.data=[9]f32{
        bigger/width,   0,              0,
        0,              bigger/height,  0,
        0,              0,              1,
    }};
}

pub fn setPos(self: *Camera, x: f32, y: f32) void {
    self.view_matrix.data[6] = -x;
    self.view_matrix.data[7] = -y;
}

pub fn move(self: *Camera, x: f32, y: f32) void {
    self.view_matrix.data[6] += -x;
    self.view_matrix.data[7] += -y;
}

pub fn getPos(self: Camera) Vec2 {
    const x = self.view_matrix.data[6];
    const y = self.view_matrix.data[7];
    return .{.x=-x, .y=-y};
}

pub fn zoom(self: *Camera, mag: f32) void {
    self.view_matrix.data[0] *= mag;
    self.view_matrix.data[1] *= mag;
    self.view_matrix.data[3] *= mag;
    self.view_matrix.data[4] *= mag;
}

pub fn setZoom(self: *Camera, mag: f32) void {
    const v1 = Vec2.gen(self.view_matrix.data[0], self.view_matrix.data[1]).normalize();
    const v2 = Vec2.gen(self.view_matrix.data[3], self.view_matrix.data[4]).normalize();
    self.view_matrix.data[0] = v1.x * mag;
    self.view_matrix.data[1] = v1.y * mag;
    self.view_matrix.data[3] = v2.x * mag;
    self.view_matrix.data[4] = v2.y * mag;
}

pub fn getZoom(self: Camera) f32 {
    const v1 = Vec2.gen(self.view_matrix.data[0], self.view_matrix.data[1]);
    return v1.length();

}
