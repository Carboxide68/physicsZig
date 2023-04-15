const std = @import("std");
const c = @import("c.zig");
const Shader = @import("shader.zig").Shader;
const Buffer = @import("buffer.zig").Buffer;
const Camera = @import("Camera.zig");
const VertexArray = @import("buffer.zig").VertexArray;

const QTG = @This();
const Point = extern struct {
    position: [2]f32,
    id: u32,
    _pad: u32 = undefined,
};

const AuxData = extern struct {
    velocity: [2]f32,
};

pub const Config = struct {
    pos: [2]f32 = .{ 0, 0 },
    size: [2]f32 = .{ 10, 10 },

    vel_mod: f32 = 0.5,

    point_radius: f32 = 0.01,
};

const ProgramHandler = struct {
    hash_sort_stage1: Shader,
    accumulate: Shader,
    sort: Shader,
    physics: Shader,

    drawer: Shader,

    points: Buffer,
    copy: Buffer,
    aux: Buffer,
    aux_copy: Buffer,
    buckets: Buffer,
    inv_buffer: Buffer,

    vao: VertexArray,
    v_buffer: Buffer,

    const circle_polygon_size = 16;
    pub fn init() !ProgramHandler {
        var ph: ProgramHandler = undefined;
        ph.hash_sort_stage1 = try Shader.initFile("src/shaders/hash_sort_stage1.os");
        ph.accumulate = try Shader.initFile("src/shaders/accumulate.os");
        ph.sort = try Shader.initFile("src/shaders/sort.os");
        ph.drawer = try Shader.initFile("src/shaders/circle_shader.os");
        ph.physics = try Shader.initFile("src/shaders/physics.os");

        ph.vao = VertexArray.init();
        ph.points = Buffer.init(0, .static_read);
        ph.aux = Buffer.init(0, .static_read);
        ph.copy = Buffer.init(0, .static_read);
        ph.aux_copy = Buffer.init(0, .static_read);
        // Last 16 elements are reserved for accumulations
        ph.buckets = Buffer.init(
            (1 + 16 + std.math.pow(usize, 2, 16)) * @sizeOf(u32),
            .static_read,
        );
        ph.inv_buffer = Buffer.init(10000000, .static_read);

        const circle_vertex_data = blk: {
            var data: [circle_polygon_size + 1][2]f32 = undefined;
            data[0] = .{ 0.0, 0.0 };

            for (data[1..], 0..) |*poly, i| {
                const fi = @intToFloat(f32, i);
                const fi2 = @intToFloat(f32, circle_polygon_size - 1);
                const angle: f32 = std.math.pi * 2.0 * fi / fi2;
                poly.* = .{ std.math.cos(angle), std.math.sin(angle) };
            }
            break :blk data;
        };
        ph.v_buffer = Buffer.init(
            @sizeOf(f32) * circle_vertex_data.len * 2,
            .static_draw,
        );
        try ph.v_buffer.subData(
            0,
            @sizeOf(f32) * circle_vertex_data.len * 2,
            circle_vertex_data,
        );

        ph.vao = VertexArray.init();
        ph.vao.bindVertexBuffer(ph.v_buffer, 0, 0, 8);
        ph.vao.setLayout(0, 2, 0, .float);

        return ph;
    }

    pub fn destroy(self: *ProgramHandler) void {
        self.vao.destroy();
        self.points.destroy();
        self.aux.destroy();
        self.buckets.destroy();
        self.copy.destroy();
        self.aux_copy.destroy();
        self.inv_buffer.destroy();
        self.v_buffer.destroy();

        self.hash_sort_stage1.destroy();
        self.accumulate.destroy();
        self.sort.destroy();
        self.drawer.destroy();
        self.physics.destroy();
    }

    pub fn newPoints(self: *ProgramHandler, points: []Point, aux: []AuxData) !void {
        std.debug.assert(points.len == aux.len);
        self.points.realloc(
            points.len * @sizeOf(Point),
            .static_read,
        );
        self.copy.realloc(
            points.len * @sizeOf(Point),
            .static_read,
        );
        self.aux.realloc(
            aux.len * @sizeOf(AuxData),
            .static_read,
        );
        self.aux_copy.realloc(
            aux.len * @sizeOf(AuxData),
            .static_read,
        );
        try self.points.subData(
            0,
            points.len * @sizeOf(Point),
            points,
        );
        try self.aux.subData(
            0,
            aux.len * @sizeOf(AuxData),
            aux,
        );
    }

    pub fn execute(self: *ProgramHandler, size: [2]f32, pos: [2]f32, radius: f32, ts: f32) void {
        self.buckets.clear(0, self.buckets.size) catch unreachable;
        self.inv_buffer.clear(0, self.inv_buffer.size) catch unreachable;
        self.inv_buffer.bindAll(.shader_storage, 1) catch unreachable;

        self.aux_copy.copy(
            self.aux,
            0,
            0,
            self.aux.size,
        ) catch unreachable;
        self.hash_sort_stage1.bind();
        self.points.bindAll(.shader_storage, 0) catch unreachable;
        self.copy.bindAll(.shader_storage, 2) catch unreachable;
        self.buckets.bindRange(
            .shader_storage,
            3,
            @sizeOf(u32),
            self.buckets.size - @sizeOf(u32),
        ) catch unreachable;

        self.hash_sort_stage1.uniform(size, "u_size");
        self.hash_sort_stage1.uniform(pos, "u_pos");

        c.glDispatchCompute(4, 4, 4);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.accumulate.bind();
        c.glDispatchCompute(1, 1, 1);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.buckets.bindAll(.shader_storage, 3) catch unreachable;
        self.sort.bind();
        c.glDispatchCompute(4, 4, 4);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.copy.copy(
            self.points,
            0,
            0,
            self.points.size,
        ) catch unreachable;
        c.glMemoryBarrier(c.GL_BUFFER_UPDATE_BARRIER_BIT);

        self.physics.bind();
        self.physics.uniform(radius, "u_radius");
        self.physics.uniform(ts, "u_ts");
        self.physics.uniform(size, "u_size");
        self.aux.bindAll(.shader_storage, 4) catch unreachable;
        self.aux_copy.bindAll(.shader_storage, 5) catch unreachable;
        c.glDispatchCompute(1, 1, 1);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);
    }

    pub fn drawPoints(self: *ProgramHandler, camera: Camera, radius: f32) void {
        self.points.bindAll(.shader_storage, 0) catch unreachable;
        self.aux.bindAll(.shader_storage, 1) catch unreachable;
        self.drawer.bind();
        self.vao.bind();
        self.drawer.uniform(camera.getAssembled(), "u_assembled_matrix");
        self.drawer.uniform(radius, "u_radius");
        self.vao.drawArraysInstanced(
            .triangle_fan,
            0,
            circle_polygon_size + 1,
            @intCast(u32, @divExact(self.points.size, @sizeOf(Point))),
        );
    }
};

a: std.mem.Allocator,
ph: ProgramHandler,
config: Config,

pub fn init(a: std.mem.Allocator, config: Config) !QTG {
    var qtg: QTG = undefined;
    qtg.a = a;
    qtg.ph = try ProgramHandler.init();
    qtg.config = config;

    return qtg;
}

pub fn destroy(self: *QTG) void {
    self.ph.destroy();
}

pub fn tick(self: *QTG, ts: f32) void {
    self.ph.execute(
        self.config.size,
        self.config.pos,
        self.config.point_radius,
        ts,
    );
}

pub fn draw(self: *QTG, camera: Camera) void {
    self.ph.drawPoints(camera, self.config.point_radius);
}

pub fn generatePoints(self: *QTG, count: usize) void {
    var rndm = std.rand.DefaultPrng.init(@intCast(
        u64,
        std.time.nanoTimestamp() >> 64,
    ));
    var random = rndm.random();
    const points = self.a.alloc(Point, count) catch unreachable;
    const velocities = self.a.alloc(AuxData, count) catch unreachable;

    for (points, velocities, 0..) |*point, *vel, i| {
        point.id = @intCast(u32, i);
        const x = (random.float(f32) - 0.5) * 2 * self.config.size[0] + self.config.pos[0];

        const y = (random.float(f32) - 0.5) * 2 * self.config.size[1] + self.config.pos[1];

        const vx = (random.float(f32) - 0.5) * 2 * self.config.vel_mod;
        const vy = (random.float(f32) - 0.5) * 2 * self.config.vel_mod;

        point.position = .{ x, y };
        vel.velocity = .{ vx, vy };
    }
    self.ph.newPoints(points, velocities) catch unreachable;
    self.a.free(points);
    self.a.free(velocities);
}
