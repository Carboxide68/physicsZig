const std = @import("std");
const c = @import("c.zig");
const common = @import("common.zig");
const QuadTree = @import("quadtree.zig");
const v = @import("vector.zig");
const Buffer = @import("buffer.zig").Buffer;
const VertexArray = @import("buffer.zig").VertexArray;
const Shader = @import("shader.zig").Shader;
const Camera = @import("camera.zig");
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
        var p = a.alloc(Vec2, size) catch return .{};
        var s = a.alloc(Vec2, size) catch return .{};
        var m = a.alloc(f32, size) catch return .{};
        return .{
            .positions=p,
            .velocities=s,
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

    node_count: usize = 10000,
    node_radius: f32 = 0.002,

    size: Vec2 = .{.x=1,.y=1},
    time_step: f32 = 0.0005,
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
    engine.nodes = Nodes.init(config.node_count, a);


    const seed = 9;
    var mesa = std.rand.DefaultPrng.init(seed);
    var prng = mesa.random();

    const b = config.size;

    for (engine.nodes.positions) |*pos, i| {
        const r = config.node_radius;
        engine.nodes.masses[i] = 0.7 * prng.float(f32) + 0.3;
        pos.x = (b.x - r) * (prng.float(f32) * 2 - 1);
        pos.y = (b.y - r) * (prng.float(f32) * 2 - 1);
        const angle = prng.float(f32) * 2 * std.math.pi;
        const speed = prng.float(f32) * 4;
        engine.nodes.velocities[i] = (Vec2{.x=@cos(angle), .y=@sin(angle)}).sMult(speed);
    }

    engine.qt = QuadTree.init(a, 10, Vec2.init(0), config.size);
    engine.config = config;

    engine.box = .{
        .{Vec2{.x=-b.x, .y= b.y}, Vec2{.x= b.x, .y= b.y}},
        .{Vec2{.x= b.x, .y= b.y}, Vec2{.x= b.x, .y=-b.y}},
        .{Vec2{.x= b.x, .y=-b.y}, Vec2{.x=-b.x, .y=-b.y}},
        .{Vec2{.x=-b.x, .y=-b.y}, Vec2{.x=-b.x, .y= b.y}},
    };
    return engine;
}

fn checkAndCollide(node1: Node, node2: Node, config: Config) bool {
    const r = config.node_radius * 2;
    const between = node1.pos.sub(node2.pos.*);
    const len_between2 = between.dot(between);
    if (r * r < len_between2) return false;
    
    const velo_diff = node1.vel.sub(node2.vel.*);
    const velo_betw_dot = velo_diff.dot(between); 
    if (velo_betw_dot >= 0) return false;

    const velocity = between.sMult(velo_betw_dot/len_between2);
    const mass_div2 = 2.0/(node1.mass.* + node2.mass.*);
    node1.vel.* = node1.vel.sub(velocity.sMult(node2.mass.* * mass_div2));
    node2.vel.* = node2.vel.add(velocity.sMult(node1.mass.* * mass_div2));
    return true;
}

fn lineCollide(node: Node, line: [2]Vec2, config: Config) Vec2 {
    const zero = Vec2{.x=0, .y=0};
    const l_diff = line[1].sub(line[0]);
    const between = node.pos.sub(line[0]);

    if (Vec2.dot(l_diff, between) < 0) return zero;

    const orth_line = Vec2{.x=-l_diff.y, .y=l_diff.x};
    const normal_orth_line = orth_line.normalize();

    if (Vec2.dot(orth_line, orth_line) < Vec2.dot(between, between)) return zero;
    
    const len_between = Vec2.dot(normal_orth_line, between);
    if (std.math.absFloat(len_between) > config.node_radius) return zero;
    const to_line = normal_orth_line.sMult(Vec2.dot(normal_orth_line, node.vel.*));
    return to_line.sMult(-2.0);
}

pub fn doTick(self: *Engine) void {

    self.qt.build(@ptrCast([*][2]f32, self.nodes.positions.ptr)[0..self.nodes.positions.len]);

    const time = common.Timer(@src());
    defer _ = time.endPrint();

    const ts = self.config.time_step;
    for (self.qt.points) |point, i| {
        const this = self.nodes.get(i);
        for (point) |index| {
            if (index == ~@as(usize, 0)) break;
            var head = index + 1;
            while (self.qt._quadtree_data[head].point.code == .Point): (head += 1) {
                const p = self.qt._quadtree_data[head].point;
                if (p.reference <= i) continue;
                const other = self.nodes.get(p.reference);
                _ = checkAndCollide(this, other, self.config);
            }
        }

        var line_vel: Vec2 = Vec2.init(0);
        for (self.box) |line| {
            line_vel = line_vel.add(lineCollide(this, line, self.config));
        }

        this.vel.* = this.vel.add(line_vel);
        this.pos.* = this.pos.add(this.vel.sMult(ts));
    }
}

pub fn draw(self: Engine, camera: Camera) void {

    const S = struct {
        var vao: VertexArray = undefined;
        var vbo: Buffer = undefined;
        var node_buffer: Buffer = undefined;
        var initialized: bool = false;

        var draw_quadtree: bool = true;

        var circle_shader: Shader = undefined;
        const circle_polygon_size = 32;
        const circle_vertex_data = blk: {
            var data: [circle_polygon_size + 1][2]f32 = undefined;
            data[0] = .{ 0.0, 0.0 };

            for (data[1..]) |*poly, i| {
                const fi = @intToFloat(f32, i);
                const fi2 = @intToFloat(f32, circle_polygon_size - 1);
                const angle: f32 = std.math.pi * 2.0 * fi / fi2;
                poly.* = .{ std.math.cos(angle), std.math.sin(angle) };
            }
            break :blk data;
        };
    };
    if (!S.initialized) {
        S.initialized = true;

        S.vao = VertexArray.init();
        S.vbo = Buffer.init(@sizeOf([2]f32) * (S.circle_polygon_size + 1), .static_draw);
        S.vbo.subData(0, @sizeOf([2]f32) * (S.circle_polygon_size + 1), common.toData(&S.circle_vertex_data[0])) catch unreachable;
        S.node_buffer = Buffer.init(0, .stream_draw);
        S.vao.bindVertexBuffer(S.vbo, 0, 0, 8);
        S.vao.setLayout(0, 2, 0, .float);
        S.circle_shader = Shader.initFile("src/circle_shader.os") catch unreachable;
    }

    _ = c.igBegin("Engine", 0, 0);
    _ = c.igText("Node count: %d", self.config.node_count);
    _ = c.igText("Node radius: %f", self.config.node_radius);
    if (common.imButton("Print Quadtree")) {
        QuadTree.print(self.qt._quadtree_data);
    }
    _ = c.igCheckbox("Draw Quadtree", &S.draw_quadtree);
    _ = c.igEnd();

    if (S.draw_quadtree)
        self.qt.draw(camera);

    S.node_buffer.realloc(@sizeOf(Vec2) * self.nodes.positions.len, .stream_draw);
    S.node_buffer.subData(0, @sizeOf(Vec2) * self.nodes.positions.len, common.toData(&self.nodes.positions[0])) catch unreachable;
    S.node_buffer.bindRange(.shader_storage_buffer, 0, 0, @intCast(i64, @sizeOf(Vec2) * self.nodes.positions.len)) catch unreachable;

    S.vao.bind();
    S.circle_shader.bind();
    S.circle_shader.uniform(self.config.node_radius, "u_radius");
    S.circle_shader.uniform([3]f32{ 0.7, 0, 0 }, "u_color");
    S.circle_shader.uniform(camera.getAssembled(), "u_assembled_matrix");
    VertexArray.drawArraysInstanced(.triangle_fan, 0, S.circle_vertex_data.len, @truncate(u32, self.nodes.positions.len));
}
