const std = @import("std");
const common = @import("common.zig");
const v = @import("vector.zig");
const Vec2 = v.Vec2;
const Mat3 = v.Mat3;
const Allocator = std.mem.Allocator;
const co_log = std.log.scoped(.co);
const tracy = @import("tracy.zig");

const QuadTree = @This();

const Sorter = struct {
    buckets: []u32 = &.{},
    a: Allocator,

    pub fn init(a: Allocator) !Sorter {
        return Sorter{
            .buckets = try a.alloc(u32, @as(usize, 1) << 16),
            .a = a,
        };
    }

    pub fn destroy(self: *Sorter) void {
        if (self.buckets.len == 0) {
            return;
        }
        self.a.free(self.buckets);
    }

    pub fn sort(self: *Sorter, points: []Point, hashes: []const u32) void {
        const t = std.time.nanoTimestamp();
        defer QuadTree.Timings.sort_points = std.time.nanoTimestamp() - t;

        std.debug.assert(points.len == hashes.len);
        var copy = self.a.alloc(Point, points.len) catch unreachable;
        defer _ = self.a.free(copy);

        std.mem.copy(Point, copy, points);
        std.mem.set(u32, self.buckets, 0);

        for (hashes) |h| {
            self.buckets[h] += 1;
        }

        var tot: u32 = 0;
        for (self.buckets) |*b| {
            const tmp = b.*;
            b.* = tot;
            tot += tmp;
        }

        for (copy) |c| {
            const h = hashes[c.id];
            points[self.buckets[h]] = c;
            self.buckets[h] += 1;
        }
    }

    fn swap(comptime T: type, first: *T, second: *T) void {
        const tmp = first.*;
        first.* = second.*;
        second.* = tmp;
    }
};

pub const Config = struct {
    pos: Vec2,
    size: Vec2,

    vel_mod: f32 = 0.5,

    point_radius: f32 = 0.01,
};

pub const Point = struct {
    position: [2]f32,
    id: u32,
};

pub const Timings = struct {
    pub var build: i128 = 0;
    pub var gen_points: i128 = 0;
    pub var hash: i128 = 0;
    pub var sort_points: i128 = 0;
    pub var do_tick: i128 = 0;
    pub var draw: i128 = 0;
};

config: Config,
points: []Point = &.{},
velocities: [][2]f32 = &.{},
hashes: []u32 = &.{},
box: [4][2][2]f32 = undefined,

sorter: Sorter,

a: Allocator,

pub fn init(a: Allocator, config: Config) !QuadTree {
    const x = config.size.x;
    const y = config.size.y;
    const box: [4][2][2]f32 = .{
        .{ .{ -x, y }, .{ x, y } },
        .{ .{ x, y }, .{ x, -y } },
        .{ .{ x, -y }, .{ -x, -y } },
        .{ .{ -x, -y }, .{ -x, y } },
    };
    return QuadTree{ .box = box, .config = config, .a = a, .sorter = try Sorter.init(a) };
}

pub fn destroy(self: *QuadTree) void {
    if (self.points.len != 0) self.a.free(self.points);
    if (self.hashes.len != 0) self.a.free(self.hashes);
    self.sorter.destroy();
}

pub fn doTick(qt: *QuadTree, ts: f32) void {
    const t = std.time.nanoTimestamp();
    defer QuadTree.Timings.do_tick = std.time.nanoTimestamp() - t;

    const r = qt.config.point_radius;
    for (qt.points, 0..) |*point, k| {
        const id = point.id;
        const x = &point.position[0];
        const y = &point.position[1];
        const vel = &qt.velocities[id];
        const POINTS = [4][2]f32{
            [2]f32{ x.* - r, y.* + r },
            [2]f32{ x.* + r, y.* + r },
            [2]f32{ x.* - r, y.* - r },
            [2]f32{ x.* + r, y.* - r },
        };
        var hashes = [4]?u32{ null, null, null, null };
        pnt: for (POINTS) |p| {
            if (p[0] >= qt.config.size.x or p[0] <= -qt.config.size.x or p[1] >= qt.config.size.y or p[1] <= -qt.config.size.y) continue;
            const pn = [2]f32{
                p[0] / qt.config.size.x,
                p[1] / qt.config.size.y,
            };
            const h = hash(pn);
            const end = qt.sorter.buckets[h];
            const start = blk: {
                if (h == 0) {
                    break :blk 0;
                } else {
                    break :blk qt.sorter.buckets[h - 1];
                }
            };
            for (&hashes) |*mb_h| {
                if (mb_h.*) |rh| {
                    if (h == rh) {
                        continue :pnt;
                    }
                } else {
                    mb_h.* = h;
                    break;
                }
            }

            for (qt.points[start..end], start..) |other, i| {
                if (i <= k) continue;
                const vo = &qt.velocities[other.id];
                _ = collide(
                    .{ x.*, y.* },
                    .{ other.position[0], other.position[1] },
                    vel,
                    vo,
                    qt.config.point_radius,
                );
            }
        }
        var line_vel = [2]f32{ 0, 0 };
        for (qt.box) |line| {
            const tmp = lineCollide(
                .{ x.*, y.* },
                .{ vel[0], vel[1] },
                line,
                qt.config.point_radius,
            );
            line_vel[0] += tmp[0];
            line_vel[1] += tmp[1];
        }

        vel.* = [2]f32{ vel[0] + line_vel[0], vel[1] + line_vel[1] };
        x.* += vel[0] * ts;
        y.* += vel[1] * ts;
    }
}

pub fn generatePoints(self: *QuadTree, count: u32) void {
    const start = std.time.nanoTimestamp();
    defer QuadTree.Timings.gen_points = std.time.nanoTimestamp() - start;
    var rndm = std.rand.DefaultPrng.init(@intCast(
        u64,
        std.time.nanoTimestamp() >> 64,
    ));
    var random = rndm.random();
    if (self.points.len != 0) {
        _ = self.a.resize(self.points, count);
        _ = self.a.resize(self.velocities, count);
    } else {
        self.points = self.a.alloc(Point, count) catch unreachable;
        self.velocities = self.a.alloc([2]f32, count) catch unreachable;
    }

    for (self.points, self.velocities, 0..) |*point, *vel, i| {
        point.id = @intCast(u32, i);
        const x = (random.float(f32) - 0.5) * 2 * self.config.size.x;
        const y = (random.float(f32) - 0.5) * 2 * self.config.size.y;
        //const vx = (random.float(f32) - 0.5) * 2 * self.config.vel_mod;
        //const vy = (random.float(f32) - 0.5) * 2 * self.config.vel_mod;
        const vx = random.float(f32) * 5;
        const vy = 0;
        point.position = .{ x, y };
        vel.* = .{ vx, vy };
    }
}

pub fn generateHashes(self: *QuadTree) void {
    const t = std.time.nanoTimestamp();
    defer QuadTree.Timings.hash = std.time.nanoTimestamp() - t;

    if (self.hashes.len != 0) {
        _ = self.a.resize(self.hashes, self.points.len);
    } else {
        self.hashes = self.a.alloc(u32, self.points.len) catch unreachable;
    }
    for (self.points) |point| {
        const p = [2]f32{
            point.position[0] / self.config.size.x,
            point.position[1] / self.config.size.y,
        };
        if (p[0] > 1 or p[0] < -1 or p[1] > 1 or p[1] < -1) continue;
        const h = &self.hashes[point.id];
        h.* = hash(p);
    }
}

pub fn sortPoints(self: *QuadTree) void {
    self.sorter.sort(self.points, self.hashes);
    if (!std.sort.isSorted(
        Point,
        self.points,
        self.hashes,
        struct {
            pub fn lesser(hashes: []const u32, lhs: Point, rhs: Point) bool {
                return hashes[lhs.id] < hashes[rhs.id];
            }
        }.lesser,
    )) {
        for (self.points) |p| {
            std.debug.print("Point {:>3}: {b:0>16}\n", .{ p.id, self.hashes[p.id] });
        }
        unreachable;
    }
}

fn hash(point: [2]f32) u32 {
    const DEPTH = 8;
    const MAX_INT = std.math.maxInt(i32);
    const HALF_MAX_INT = MAX_INT / 2;

    var xq = @floatToInt(i32, point[0] * MAX_INT);
    var yq = @floatToInt(i32, point[1] * MAX_INT);
    var hashed: u32 = 0;
    var exp = @as(u32, 1) << @as(u5, (DEPTH - 1) * 2);

    for (0..DEPTH) |_| {
        const x_flag: i32 = if (xq > 0) 1 else 0;
        const y_flag: i32 = if (yq > 0) 0 else 1;

        hashed |= @intCast(u32, (y_flag << 1) | x_flag) * exp;
        exp = exp >> 2;

        xq = (xq + (HALF_MAX_INT - MAX_INT * x_flag)) * 2;
        yq = (yq + (HALF_MAX_INT - MAX_INT * (1 - y_flag))) * 2;
    }
    return hashed;
}

fn collide(p1: [2]f32, p2: [2]f32, v1: *[2]f32, v2: *[2]f32, r: f32) bool {
    const between = [2]f32{ p1[0] - p2[0], p1[1] - p2[1] };
    const len_between2 = between[0] * between[0] + between[1] * between[1];
    if (r * r * 4 < len_between2) return false;

    const velo_diff = [2]f32{ v1[0] - v2[0], v1[1] - v2[1] };
    const velo_betw_dot = velo_diff[0] * between[0] + velo_diff[1] * between[1];
    if (velo_betw_dot >= 0) return false;

    const vel_coef = velo_betw_dot / len_between2;
    const velocity = [2]f32{ between[0] * vel_coef, between[1] * vel_coef };
    v1.* = [2]f32{ v1[0] - velocity[0], v1[1] - velocity[1] };
    v2.* = [2]f32{ v2[0] + velocity[0], v2[1] + velocity[1] };
    return true;
}

fn lineCollide(p: [2]f32, vel: [2]f32, line: [2][2]f32, r: f32) [2]f32 {
    const PADDING = 0.1;

    const zero = [2]f32{ 0, 0 };
    const l_diff = [2]f32{ line[1][0] - line[0][0], line[1][1] - line[0][1] };
    const between = [2]f32{ p[0] - line[0][0], p[1] - line[0][1] };

    if (l_diff[0] * between[0] + l_diff[1] * between[1] < 0) return zero;

    const orth_line = [2]f32{ -l_diff[1], l_diff[0] };
    const l_length2 = l_diff[0] * l_diff[0] + l_diff[1] * l_diff[1];
    const l_length = @sqrt(l_length2);
    const normal_orth_line = [2]f32{ orth_line[0] / l_length, orth_line[1] / l_length };

    if (l_length2 < between[0] * between[0] + between[1] * between[1]) return zero;

    const len_between = normal_orth_line[0] * between[0] + normal_orth_line[1] * between[1];
    const vel_between = normal_orth_line[0] * vel[0] + normal_orth_line[1] * vel[1];
    var len_sign: f32 = if (len_between > 0) 1 else -1;
    var vel_sign: f32 = if (vel_between > 0) 1 else -1;
    if (len_sign == vel_sign) return zero;

    if (std.math.fabs(len_between) > r + PADDING) return zero;
    var velocity = normal_orth_line[0] * vel[0] + normal_orth_line[1] * vel[1];
    velocity *= -2;
    const to_line = [2]f32{ normal_orth_line[0] * velocity, normal_orth_line[1] * velocity };
    return to_line;
}
