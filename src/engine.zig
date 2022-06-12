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
const Vec3 = v.Vec3;
const Vec4 = v.Vec4;
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

    node_count: usize = 20000,
    node_radius: f32 = 0.02,

    size: Vec2 = .{.x=40,.y=2.5},
    time_step: f32 = 0.002,
};

const Engine = @This();

_a: std.mem.Allocator,
nodes: Nodes = .{},
colors: []Vec4 = ([_]Vec4{})[0..0],
qt: QuadTree = undefined,
config: Config,
box: [4][2]Vec2,

pub fn init(a: std.mem.Allocator, config: Config) Engine {

    var engine: Engine = undefined;
    engine._a = a;
    engine.nodes = Nodes.init(config.node_count, a);
    engine.colors = engine._a.alloc(Vec4, config.node_count) catch ([_]Vec4{})[0..0];

    const seed = 9;
    var mesa = std.rand.DefaultPrng.init(seed);
    var prng = mesa.random();

    const b = config.size;

    for (engine.nodes.positions) |*pos, i| {
        const r = config.node_radius;
        engine.nodes.masses[i] = 0.7 * prng.float(f32) + 0.3;
        pos.x = (b.x - r) * (prng.float(f32) * 2 - 1);
        pos.y = (b.y - r) * (prng.float(f32) * 2 - 1);
        //const angle = prng.float(f32) * 2 * std.math.pi;
        const angle: f32 = 0;
        const speed = prng.float(f32) * 8;
        engine.nodes.velocities[i] = (Vec2{.x=@cos(angle), .y=@sin(angle)}).sMult(speed);
        const b_w: f32 = if (pos.x/(b.x*2) < 0) 0 else 1;
        engine.colors[i] = .{.x=b_w, .y=0, .z=1 - b_w, .w=0};
    }

    engine.qt = QuadTree.init(a, 10, Vec2.init(0), config.size);
    engine.qt.config.node_count_in_one = 6;
    engine.qt.config.point_radius = config.node_radius;
    engine.config = config;

    engine.box = .{
        .{Vec2{.x=-b.x, .y= b.y}, Vec2{.x= b.x, .y= b.y}},
        .{Vec2{.x= b.x, .y= b.y}, Vec2{.x= b.x, .y=-b.y}},
        .{Vec2{.x= b.x, .y=-b.y}, Vec2{.x=-b.x, .y=-b.y}},
        .{Vec2{.x=-b.x, .y=-b.y}, Vec2{.x=-b.x, .y= b.y}},
    };
    return engine;
}

pub fn destroy(self: *Engine) void {
    self.qt.destroy();
    self.nodes.destroy(self._a);
    if (self.colors.len != 0) self._a.free(self.colors);
}

fn checkAndCollide(node1: Node, node2: Node, config: Config) bool {
    const r = config.node_radius;
    const between = node1.pos.sub(node2.pos.*);
    const len_between2 = between.dot(between);
    if (r * r * 4 < len_between2) return false;
    
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

    const S = struct {
        var do = true;
        var hit_last = false;
    };

    if (!S.do) return;

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
    const first = self.nodes.get(0);
    const second = self.nodes.get(1);
    if (second.pos.sub(first.pos.*).length2() <= 4 * self.config.node_radius * self.config.node_radius) {
        if (S.hit_last) S.do = false;
        S.hit_last = true;
        //for (self.qt.points) |point| {
        //    for (point) |p| {
        //        std.debug.print(" {} |", .{p});
        //    }
        //    std.debug.print("\n", .{});
        //}
        for (self.qt._cells) |cell| {
            std.debug.print(" {} |", .{cell.hash});
        }
        std.debug.print("\n", .{});
    } else {
        S.hit_last = false;
    }
}

pub fn draw(self: *Engine, camera: Camera) void {

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
    const t_build = @truncate(i64, @divFloor(QuadTree.Timings.build, 1000));
    const t_gen_points = @truncate(i64, @divFloor(QuadTree.Timings.gen_points, 1000));
    const t_sort_points = @truncate(i64, @divFloor(QuadTree.Timings.sort_points, 1000));
    const t_build_quadtree = @truncate(i64, @divFloor(QuadTree.Timings.build_quadtree, 1000));
    const t_second_sort = @truncate(i64, @divFloor(QuadTree.Timings.second_sort, 1000));
    const t_draw = @truncate(i64, @divFloor(QuadTree.Timings.draw, 1000));
    _ = c.igText("Timings:\n\tBuild: %lld\n\tGen Points: %lld\n\tSort Points: %lld\n\tBuild Quadtree: %lld\n\tSecond Sort: %lld\n\tDraw: %lld", 
            t_build, t_gen_points, t_sort_points, t_build_quadtree, t_second_sort, t_draw
        );
    _ = c.igEnd();

    if (S.draw_quadtree)
        self.qt.draw(camera);

    S.node_buffer.realloc(@sizeOf(Vec2) * self.nodes.positions.len + @sizeOf(Vec4) * self.colors.len, .stream_draw);
    S.node_buffer.subData(0, @sizeOf(Vec2) * self.nodes.positions.len, common.toData(&self.nodes.positions[0])) catch unreachable;
    S.node_buffer.subData(@sizeOf(Vec2) * self.nodes.positions.len, @sizeOf(Vec4) * self.colors.len, common.toData(&self.colors[0])) catch unreachable;
    S.node_buffer.bindRange(
        .shader_storage_buffer, 0, 0, 
        @intCast(i64, @sizeOf(Vec2) * self.nodes.positions.len)
        ) catch unreachable;
    S.node_buffer.bindRange(
        .shader_storage_buffer, 1, 
        @intCast(i64, @sizeOf(Vec2) * self.nodes.positions.len), 
        @intCast(i64, @sizeOf(Vec4) * self.colors.len), 
        ) catch unreachable;

    S.circle_shader.bind();
    S.circle_shader.uniform(self.config.node_radius, "u_radius");
    S.circle_shader.uniform([3]f32{ 0.7, 0, 0 }, "u_color");
    S.circle_shader.uniform(camera.getAssembled(), "u_assembled_matrix");
    S.vao.drawArraysInstanced(.triangle_fan, 0, S.circle_vertex_data.len, @truncate(u32, self.nodes.positions.len));
}

