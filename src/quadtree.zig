
const std = @import("std");
const common = @import("common.zig");
const QuadTree = @This();
const v = @import("vector.zig");
const Vec2 = v.Vec2;
const Mat3 = v.Mat3;

const Allocator = std.mem.Allocator;

//Quadtree. The struct first contains a list with all the points it contains.
//Each point also contians a reference to up to 4 cells.
//These pointers have 2 bits for each possible path, so the max depth is 32 if the reference is a u64.
//First store the byte-offsets to the reference levels.
//Each level contains metadata seen in the struct QuadTreeLevel

pub const Config = struct {
    position: [2]f32,
    width: f32,
    height: f32,
    max_depth: u32 = 10,
    point_radius: f32 = 0.1,
    node_count_in_one: u32 = 4,
};

pub const Info = struct {
    qtls: usize = 0,
    points: usize = 0,
};

config: Config,
info: Info = .{},

_a: Allocator,
points: [][4]Cell = ([_][4]Cell{})[0..0],
_quadtree_data: []Word = ([_]Word{})[0..0],
_indices: []usize = ([_]usize{})[0..0],

pub fn init(a: Allocator, max_depth: u32, position: [2]f32, width: f32, height: f32) QuadTree {
    return .{
        .config = .{
            .position = position,
            .max_depth = @minimum(max_depth, Cell.MAX_DEPTH),
            .width = width,
            .height = height,
        },
        ._a = a,
    };
}

pub fn destroy(self: *QuadTree) void {
    if (self._quadtree_data.len > 0) self._a.free(self._quadtree_data);
    if (self._indices.len > 0) self._a.free(self._indices);
    if (self.points.len > 0) self._a.free(self.points);
}

pub fn getPointsInCell(self: QuadTree, cell: Cell) []u56 {
    if (cell.hash == null) return {};
    var index: usize = 0;

    var i: usize = 0;
    while (i < self.config.max_depth) : (i += 1) {
        const lvl_id = cell.level(i);
        const qtl = self._quadtree_data[index].qtl;
        index = qtl.getLevel(index, self._quadtree_data, lvl_id) orelse break;
    }

    const qtl = self._quadtree_data[index].qtl;
    const count = qtl.getPointCount();
    var points = self._a.alloc(u56, count);

    for (points) |*point| {
        index += 1;
        const next_space = self._quadtree_data[index];
        if (next_space.node != .Point) return points;
        
        const next_point = next_space.point;
        point.* = next_point.reference;
    }
    return points;
}

fn lessThanIndexSort(context: [][4]Cell, lhs: usize, rhs: usize) bool {
    const minor_lhs = lhs%4;
    const major_lhs = lhs >> 2;
    const minor_rhs = rhs%4;
    const major_rhs = rhs >> 2;
    const l = context[major_lhs][minor_lhs];
    const r = context[major_rhs][minor_rhs];

    if (l.depth == r.depth) {
        return l.hash < r.hash;
    } else return l.depth > r.depth;

}

pub fn build(self: *QuadTree, points_in: [][2]f32) void {
    const t = common.Timer(@src());
    defer _ = t.endPrint();

    self.info = .{};
    self.points = self._a.realloc(self.points, points_in.len) catch self.points;

    if (self._indices.len != points_in.len) {
        if (self._indices.len > 0) self._a.free(self._indices);
        self._indices = self._a.alloc(usize, points_in.len * 4) catch unreachable;
        for (self.points) |*point, i| {
            point.* = Cell.calc(self.config, points_in[i]);
            self._indices[i*4+0] = i*4+0;
            self._indices[i*4+1] = i*4+1;
            self._indices[i*4+2] = i*4+2;
            self._indices[i*4+3] = i*4+3;
        }
    } else {
        for (self.points) |*point, i| {
            point.* = Cell.calc(self.config, points_in[i]);
        }
    }

    std.sort.sort(usize, self._indices, self.points, lessThanIndexSort);

    self._quadtree_data = self._a.realloc(self._quadtree_data, self.config.max_depth * self._indices.len) catch self._quadtree_data;
    for (self._quadtree_data) |*s| s.int = 0;

    _ = build_tree_branch(self.config, &self.info, self.points, self._indices, self._quadtree_data, 0, 0);
}

//Takes a layer and does all the necessary operations for it 
fn build_tree_branch(config: Config, info: *Info, cells: [][4]Cell, indices: []const usize,
                     data: []Word, begin_depth: u6, offset_index: usize) usize {
    if (begin_depth >= config.max_depth) {
        var cur_index = offset_index;
        var added: [128]usize = undefined;
        var added_len: usize = 0;
        outer: for (indices[0..]) |index| {
            const i_mj = index >> 2;
            const i_mi = index % 4;
            for (added[0..added_len]) |a| {
                if (a == i_mj) continue :outer;
            }
            added[added_len] = i_mj;
            added_len += 1;

            cells[i_mj][i_mi].depth = @truncate(u6, begin_depth);
            data[cur_index].point = Point{.reference=@truncate(u56, index)};
            cur_index += 1;
            info.points += 1;
        }
        return cur_index - offset_index;
    }

    var farthest = [4]usize{0,0,0,0};
    for (indices) |index, i| {
        const i_mj = index >> 2;
        const i_mi = index % 4;
        if (cells[i_mj][i_mi].depth == 0) break;
        farthest[cells[i_mj][i_mi].level(begin_depth)] = i;
    }

    var last: usize = 0;
    var cur_index = offset_index;
    for (farthest) |qtl, subgroup| {
        if (qtl == 0) continue;
        info.qtls += 1;
        if (qtl - last <= config.node_count_in_one*4) {
            data[cur_index].qtl = .{.subgroup=@truncate(u2, subgroup), .depth = @truncate(u6, begin_depth), .word_size=@truncate(u48, qtl-last)};
            cur_index += 1;
            var added: [128]usize = undefined;
            var added_len: usize = 0;
            outer: for (indices[last..qtl]) |index| {
                const i_mj = index >> 2;
                const i_mi = index % 4;
                for (added[0..added_len]) |a| {
                    if (a == i_mj) continue :outer;
                }
                added[added_len] = i_mj;
                added_len += 1;

                if (cells[i_mj][i_mi].depth == 0) break;
                info.points += 1;

                cells[i_mj][i_mi].depth = @truncate(u6, begin_depth);
                data[cur_index].point = .{.reference=@truncate(u56, i_mj)};
                cur_index += 1;
            }
        } else {
            const size = build_tree_branch(config, info, cells, indices[last..qtl], data, begin_depth+1, cur_index+1);
            data[cur_index].qtl = .{.subgroup=@truncate(u2, subgroup), .depth = @truncate(u6, begin_depth), .word_size=@truncate(u48, size)};
            cur_index += 1 + size;
        }
        last = qtl;
    }
    return cur_index - offset_index;
}

const Buffer = @import("buffer.zig").Buffer;
const VertexArray = @import("buffer.zig").VertexArray;
const Shader = @import("shader.zig").Shader;
const Camera = @import("camera.zig");
pub fn draw(self: QuadTree, camera: Camera) void {

    const s = struct {
        var initialized = false;
        var buffer: Buffer = undefined;
        var vao: VertexArray = undefined;
        var draw_data: [][2]Vec2 = undefined;
        var shader: Shader = undefined;
    };
    if (!s.initialized) {
        s.initialized = true;
        s.vao = VertexArray.init();
        s.buffer = Buffer.init(0, .static_draw);
        s.vao.bindVertexBuffer(s.buffer, 0, 0, @sizeOf(f32) * 2);
        s.vao.setLayout(0, 2, 0, .float);
        s.draw_data = self._a.alloc([2]Vec2, 0) catch unreachable;
        s.shader = Shader.initFile("src/line_shader.os") catch .{._program_handle=0};
    }

    const subgroup_lookup = [4]Vec2{
        Vec2{.x=-1, .y= 1},
        Vec2{.x= 1, .y= 1},
        Vec2{.x=-1, .y=-1},
        Vec2{.x= 1, .y=-1},
    };
    s.draw_data = self._a.realloc(s.draw_data, self.info.qtls*4 + 4) catch s.draw_data;
    if (s.draw_data.len == 0) {
        std.debug.print("Failed to allocate memory to draw_data!\n", .{});
        return;
    }
    var head: u32 = 4;
    s.draw_data[0] = [2]Vec2{Vec2{.x=-1,.y=-1}, Vec2{.x=-1, .y= 1}};
    s.draw_data[1] = [2]Vec2{Vec2{.x=-1,.y= 1}, Vec2{.x= 1, .y= 1}};
    s.draw_data[2] = [2]Vec2{Vec2{.x= 1,.y= 1}, Vec2{.x= 1, .y=-1}};
    s.draw_data[3] = [2]Vec2{Vec2{.x= 1,.y=-1}, Vec2{.x=-1, .y=-1}};

    var start_pos = Vec2{.x=0, .y=0};
    var cur_hash: Cell = .{.hash=0, .depth=0};

    for (self._quadtree_data) |word| {
        if (word.qtl.code == .Level) {
            const sb = word.qtl.subgroup;
            cur_hash.depth = word.qtl.depth;

            cur_hash.hash &= ~((~@as(u56, 0)) >> @truncate(u6, 2*cur_hash.depth));
            cur_hash.hash |= Cell.transform(cur_hash.depth, sb);

            start_pos = .{.x=0, .y=0};
            var j: u6 = 0;
            while (j < cur_hash.depth) : (j += 1) {
                const flag_bits = cur_hash.level(j);
                const x_flag = 1 & flag_bits;
                const y_flag = 2 & flag_bits;
                const fj = std.math.pow(f32, 2, -@intToFloat(f32, j+1));
                start_pos.x += if (x_flag == 0) -1*fj else  1*fj;
                start_pos.y += if (y_flag == 0)  1*fj else -1*fj;
            }

            const box_len = std.math.pow(f32, 2, -@intToFloat(f32, word.qtl.depth));
            var new_x = start_pos.x + subgroup_lookup[sb].x * box_len;
            var new_y = start_pos.y + subgroup_lookup[sb].y * box_len;

            s.draw_data[head] = .{start_pos, .{.x=start_pos.x, .y=new_y}};
            s.draw_data[head+1] = .{start_pos, .{.x=new_x, .y=start_pos.y}};
            head += 2;
        } else continue;
    }
    s.buffer.realloc(head * @sizeOf([2]Vec2), .stream_draw);
    s.buffer.subData(0, head * @sizeOf([2]Vec2), common.toData(s.draw_data)) catch {};

    const model_matrix = Mat3{.data = .{
        self.config.width/2, 0, 0,
        0, self.config.height/2, 0,
        -self.config.position[0], -self.config.position[1], 1,
    }};

    s.vao.bind();
    s.shader.bind();
    s.shader.uniform(camera.getAssembled(), "u_assembled_matrix");
    s.shader.uniform(model_matrix, "u_model_matrix");
    VertexArray.drawArrays(.lines, 0, head*2);
}

pub fn print(self: QuadTree) void {
    var tabs: usize = 0;
    for (self._quadtree_data) |data, i| {
        std.debug.print("{}\t|", .{i});
        switch (data.qtl.code) {
            .End => {std.debug.print("End", .{}); break;},
            
            .Level => {
                const qtl = data.qtl;
                tabs = qtl.depth;
                {
                    var j: usize = 0; 
                    while (j < tabs) : (j += 1) std.debug.print("  ", .{});
                }
                std.debug.print("QTL[sg: {} | depth: {} | ws: {}]", .{qtl.subgroup, qtl.depth, qtl.word_size});
            },

            .Point => {
                {
                    var j: usize = 0; 
                    while (j < tabs+1) : (j += 1) std.debug.print("  ", .{});
                }
                const point = data.point;
                std.debug.print("Point[index: {}]", .{point.reference});
            }
        }
        std.debug.print("\n", .{});
    }
}

const Codes = enum (u8) {
    End     = 0,
    Level   = 1,
    Point   = 2,
};

const Word = packed union {

    qtl: QuadTreeLevel,
    point: Point,
    int: u64,

};

const QuadTreeLevel = packed struct {

    const _size = @sizeOf(@This());

    word_size: u48,
    depth: u6,
    subgroup: u2,
    code: Codes = .Level,

    pub fn getLevel(index: usize, qt: []Word, subgroup: u32) ?usize {
        const self = qt[index].qtl;

        var i = index + 1;
        var counter: u8 = 0;
        while (counter < 4) : (counter += 1) {
            if (qt[i].qtl.code != .Level) return null;
            
            const next_level = qt[i].qtl;
            if (next_level.depth != self.depth + 1) return null;
            
            if (next_level.subgroup == subgroup) return next_level;
            i += 1 + next_level.word_size;
        }
        return null;
    }
    
    pub fn getPointCount(index: usize, qt: []Word) u32 {
        const self = qt[index].qtl;
        const next_level = qt[index+1].point;
        if (next_level.code != .Point) return 0;
        
        return self.word_size;
    }
};

const Point = packed struct {
    const _size = @sizeOf(@This());

    reference: u56,
    code: Codes = .Point,

};

const Cell = struct {
    const _size = @sizeOf(@This());
    const MAX_DEPTH = 28;

    hash: u56,
    depth: u8,

    pub fn calc(config: Config, pos: [2]f32) [4]Cell {
        var cells: [4]Cell = [_]Cell{.{.hash=0, .depth=0},}**4;
        const r = config.point_radius;
         for (cells) |*cell, i| {
            var p: [2]f32 = undefined;
            p[0] = pos[0] + (if (i & 1 == 0) -r else r);
            p[1] = pos[1] + (if (i & 2 == 0) r else -r);
            const candidate = Cell.calcPoint(config, p);
            for (cells) |c| {
                if (c.depth > 0) {
                    if (c.hash == candidate.hash) break;
                }
            } else 
                cell.* = candidate;
        }
        return cells;
    }

    pub fn calcPoint(config: Config, pos: [2]f32) Cell {
        if (config.max_depth > MAX_DEPTH) return Cell{.hash=0, .depth=0};
        var xpos = 2 * (pos[0] - config.position[0])/config.width;
        var ypos = 2 * (pos[1] - config.position[1])/config.height;

        if (xpos > 1 or xpos < -1 or
            ypos > 1 or ypos < -1) {
            return Cell{.hash=0, .depth=0};
        }

        var cell: Cell = .{.hash=0, .depth=@truncate(u6, config.max_depth)};

        var i: usize = 0;
        while (i < config.max_depth) : (i += 1) {
            const x_flag: u56 = if(xpos > 0) 1 else 0;
            const y_flag: u56 = if(ypos > 0) 1 else 0;
            cell.hash |= Cell.transform(@truncate(u56, i), x_flag | (1 - y_flag)*2);

            xpos = (xpos*2) + (1 - 2*@intToFloat(f32, x_flag));
            ypos = (ypos*2) + (1 - 2*@intToFloat(f32, y_flag));
        }

        cell.depth = @truncate(u6, i);
        return cell;
    }

    pub inline fn transform(lvl: u56, sb: u56) u56 {
        if (lvl > Cell.MAX_DEPTH-1) return 0;
        return sb << @intCast(u6, 2*(Cell.MAX_DEPTH - lvl - 1));
    }

    pub inline fn level(self: Cell, l: u6) u2 {
        if (l > self.depth) return 0;
        return @truncate(u2, self.hash >> (2*(Cell.MAX_DEPTH - l - 1)));
    }
};

test "Hash Test" {
    const config = Config{
        .position = [2]f32{0, 0},
        .max_depth = 10,
        .width = 10,
        .height = 10,
    };
    std.debug.print("Position: [{}, {}]\nWidth: {}\nHeight: {}\n", .{
        config.position[0], config.position[1], config.width, config.height
    });

    const points = [_][2]f32 {
        [2]f32{1, 1},
        [2]f32{-1, 1},
        [2]f32{-1, -1},
        [2]f32{1, -1},
        [2]f32{-3, 4},
        [2]f32{1, -3},
        [2]f32{-4, -4},
    };
    for (points) |point| {
        const cell = Cell.calcPoint(config, point);
        std.debug.print("[{}, {}]: ", .{point[0], point[1]});

        var k: u6 = 0;
        while (k < config.max_depth) : (k += 1) {
            const c = cell.level(k);
            std.debug.print("{}", .{c});
        }
        std.debug.print("\n",.{});
    }
}

test "Build QuadTree" {
    
    const seed: u64 = 9;
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    const width: f32 = 5;
    const height: f32 = 5;

    var points: [32][2]f32 = undefined;
    for (points) |*point| {
        point.*[0] = (rand.float(f32) * 2 - 1) * width/2;
        point.*[1] = (rand.float(f32) * 2 - 1) * height/2;
    }
    var tree = QuadTree.init(std.testing.allocator, 10, .{0, 0}, width, height);
    defer tree.destroy();

    tree.build(points[0..32]);

    for (tree._indices) |index, i| {
        std.debug.print("{}: ", .{i});
        const i_mi = index % 4;
        const i_mj = index >> 2;
        const cell = tree.points[i_mj][i_mi];
        var k: u6 = 0;
        while (!(k > Cell.MAX_DEPTH)) : (k += 1) {
            std.debug.print("{}", .{cell.level(k)});
        }
        std.debug.print(" : {}\n", .{tree.points[i_mj][i_mi].hash});
    }

    std.debug.print("Index Array:\n{any}\n", .{tree._indices});
}

test "print" {
    std.debug.print("\n", .{});
    const seed: u64 = 9;
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    const width: f32 = 5;
    const height: f32 = 5;

    var points: [200][2]f32 = undefined;
    for (points) |*point| {
        point.*[0] = (rand.float(f32) * 2 - 1) * width/2;
        point.*[1] = (rand.float(f32) * 2 - 1) * height/2;
        std.debug.print("Point: [{}, {}]\n", .{point[0], point[1]});
    }
    var tree = QuadTree.init(std.testing.allocator, 15, .{0, 0}, width, height);
    defer tree.destroy();

    tree.build(points[0..]);
    tree.print();
}
