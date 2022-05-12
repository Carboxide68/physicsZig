const std = @import("std");
const common = @import("common.zig");
const QuadTree = @import("quadtree.zig");
const v = @import("vector.zig");
const Vec2 = v.Vec2;
const Mat3 = v.Mat3;

pub const Node = struct {

    pos: *Vec2,
    vel: *Vec2,
    mass: *f32,

};

pub const Nodes = struct {

    positions: []Vec2 = ([_]Vec2{})[0..0],
    velocities: []Vec2 = ([_]Vec2{})[0..0],
    masses: []f32 = ([_]f32{})[0..0],

    pub fn init(size: usize, a: std.mem.Allocator) Nodes {
        var p = a.alloc(Vec2, size);
        var v = a.alloc(Vec2, size);
        var m = a.alloc(f32, size);
        return .{
            .positions=p,
            .velocities=v,
            .masses=m,
        };
    }

    pub fn destroy(self: Nodes, a: std.mem.Allocator) void {
        a.free(self.positions);
        a.free(self.velocities);
        a.free(self.masses);
    }

    pub fn get(self: Nodes, index: usize) Node {
        if (index > self.positions.len) unreachable;
        return .{
            .pos=&self.positions[index],
            .vel=&self.velocities[index],
            .mass=&self.masses[index],
        };
    }
};

pub const Config = struct {

    node_count: usize = 2000,
    node_radius: f32 = 0.01,

    size: Vec2 = .{.x=1,.y=1},
};

const Engine = @This();

_a: std.mem.Allocator,
nodes: Nodes = .{},
qt: QuadTree = undefined,
config: Config,
box: [4][2]Vec2,

pub fn init(a: std.mem.Allocator, config: Config) Engine {

    var engine: Engine = undefined;
    engine._a = a;
    engine.nodes = Nodes.init(a, config.node_count);


    const seed = 9;
    var prng = std.rand.DefaultPrng.init(seed);

    const b = config.size;

    for (engine.nodes.position) |*pos, i| {
        const r = config.node_radius;
        engine.nodes.masses[i] = 0.7 * prng.float(f32);
        pos.x = (b.x - r) * (prng.float(f32) * 2 - 1);
        pos.y = (b.y - r) * (prng.float(f32) * 2 - 1);
        const angle = prng.float(f32) * 2 * std.math.pi;
        const speed = prng.float(f32) * 15;
        engine.nodes.velocities[i] = Vec2{.x=@cos(f32, angle), .y=@sin(f32, angle)}.sMult(speed);
    }

    engine.qt = QuadTree.init(a, 10, Vec2.init(0), config.size);
    engine.config = config;

    engine.box = .{
        .{Vec2{-b.x,  b.y}, Vec2{ b.x,  b.y}},
        .{Vec2{ b.x,  b.y}, Vec2{ b.x, -b.y}},
        .{Vec2{ b.x, -b.y}, Vec2{-b.x, -b.y}},
        .{Vec2{-b.x, -b.y}, Vec2{-b.x,  b.y}},
    };
}

