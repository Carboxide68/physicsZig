const std = @import("std");
const common = @import("common.zig");
const v = @import("vector.zig");
const Vec2 = v.Vec2;
const Vec3 = v.Vec3;

const Mat3 = v.Mat3;

const PhysicsEngine = @This();


pub Config = struct {

    node_count: usize,
    node_radius: f32,

    env_dims: Vec2,


};

_seed: u64,
_rand: std.rand.Random,


pub fn init(node_count: usize, node_radius: f32, width: f32, height: f32) PhysicsEngine {

    return initWithConfig(.{
        .node_count = node_count,
        .node_radius = node_radius,
        
        .env_dims = .{.x=width, .y=height},
    });

}

pub fn initWithConfig(config: Config) PhysicsEngine {
}
