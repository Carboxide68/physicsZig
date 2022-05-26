
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
//Each level contains metadata seen in the struct QTL

pub const Config = struct {
    pos: Vec2,
    size: Vec2,

    max_depth: u32 = 10,

    point_radius: f32 = 0.1,
    node_count_in_one: u32 = 4,
};

pub const Info = struct {
    qtls: usize = 0,
    points: usize = 0,
};

pub const Timings = struct {

    pub var build: i128 = 0;
    pub var gen_points: i128 = 0;
    pub var sort_points: i128 = 0;
    pub var build_quadtree: i128 = 0;
    pub var draw: i128 = 0;
    pub var second_sort: i128 = 0;

};

config: Config,
info: Info = .{},

points: [][4]usize = ([_][4]usize{})[0..0],
_a: Allocator,
_cells: []Cell = ([_]Cell{})[0..0],
_quadtree_data: []Word = ([_]Word{})[0..0],
_indices: []usize = ([_]usize{})[0..0],

pub fn init(a: Allocator, max_depth: u32, position: Vec2, size: Vec2) QuadTree {
    return .{
        .config = .{
            .pos = position,
            .max_depth = @minimum(max_depth, Cell.MAX_DEPTH),
            .size = size,
        },
        ._a = a,
    };
}

pub fn destroy(self: *QuadTree) void {
    if (self._quadtree_data.len > 0) self._a.free(self._quadtree_data);
    if (self._indices.len > 0) self._a.free(self._indices);
    if (self._cells.len > 0) self._a.free(self._cells);
    if (self.points.len > 0) self._a.free(self.points);
}

fn lessThanIndexSort(context: []Cell, lhs: usize, rhs: usize) bool {
    const l = context[lhs];
    const r = context[rhs];

    if (l.depth == r.depth) {
        return l.hash < r.hash;
    } else return l.depth > r.depth;
}

pub fn build(self: *QuadTree, points_in: []const [2]f32) void {
    const t = common.Timer(@src());
    defer Timings.build = t.end();

    self.info = .{};
    self._cells = self._a.realloc(self._cells, points_in.len*4) catch self._cells;
    if (self._cells.len == 0) {
        std.debug.print("Failed to allocate points!\n", .{});
        return;
    }

    if (self._indices.len != points_in.len) {
        if (self._indices.len > 0) self._a.free(self._indices);
        self._indices = self._a.alloc(usize, points_in.len*4) catch unreachable;
    }

    const t_gen_points = common.Timer(@src());
    for (self._cells) |*point, i| {
        const r = self.config.point_radius;
        const offset = [2]f32{if (i & 1 == 0) -r else r, if (i & 2 == 0) r else -r};
        const p = Vec2{.x=points_in[i>>2][0] + offset[0], .y=points_in[i>>2][1] + offset[1]};
        point.* = Cell.calc(self.config, p);
        self._indices[i] = i;
    }

    Timings.gen_points = t_gen_points.end();

    //Sorting indices after point hash 
    const t_sort_points = common.Timer(@src());
    std.sort.sort(usize, self._indices, self._cells, lessThanIndexSort);
    Timings.sort_points = t_sort_points.end();

    self._quadtree_data = self._a.realloc(self._quadtree_data, self.config.max_depth * self._indices.len) catch self._quadtree_data;
    for (self._quadtree_data) |*s| s.int = 0;

    //Building tree
    const t_build_quadtree = common.Timer(@src());
    const length = buildTreeBranch(self.config, &self.info, self._cells, self._indices, self._quadtree_data, 0, 0);
    Timings.build_quadtree = t_build_quadtree.end();
    self._quadtree_data[length].int = 0;

    self.points = self._a.realloc(self.points, points_in.len) catch self.points;
    
    std.debug.print("QuadTree takes up {} bytes \n", .{8*length});
    
    //Extracting point locations
    const t_second_sort = common.Timer(@src());
    for (self.points) |*point, i| {
        point[0] = self._cells[i*4+0].hash;
        point[1] = self._cells[i*4+1].hash;
        point[2] = self._cells[i*4+2].hash;
        point[3] = self._cells[i*4+3].hash;

        std.sort.sort(usize, point[0..], {}, struct {
            pub fn lessThan(_: void, lhs: usize, rhs: usize) bool {
                return lhs < rhs;
            }}.lessThan);
        var head: usize = 0;
        var last: usize = ~@as(usize, 0);
        for (point) |p, k| {
            if (p == last or self._cells[i*4+k].depth == 0) continue;
            last = p;
            point[head] = p;
            head += 1;
        }

        for (point[head..]) |*p| {
            p.* = ~@as(usize, 0);
        }
    }
    Timings.second_sort = t_second_sort.end();
}

//Takes a layer and does all the necessary operations for it 
fn buildTreeBranch(config: Config, info: *Info, cells: []Cell, indices: []const usize,
                     data: []Word, begin_depth: u6, offset_index: usize) usize {
    if (begin_depth >= config.max_depth) {
        var cur_index = offset_index;
        for (indices) |i| {

            cells[i].depth = @truncate(u6, begin_depth);
            cells[i].hash = @truncate(u56, offset_index - 1);
            data[cur_index].point = Point{.reference=@truncate(u56, i>>2)};

            cur_index += 1;
            info.points += 1;
        }
        
        //Make sure only unique references to points exists in one cell
        std.sort.sort(Word, data[offset_index+1..cur_index], @as(u8, 0), struct {
            pub fn lessThan(_: u8, lhs: Word, rhs: Word) bool {
                return lhs.point.reference < rhs.point.reference;
            }}.lessThan);
        var head: u56 = 0;
        var l: usize = ~@as(usize, 0);
        for (data[offset_index+1..cur_index]) |p| {
            if (p.point.reference == l) continue;
            l = p.point.reference;
            data[offset_index+1+head] = p;
            head += 1;
        }

        cur_index = offset_index+1+head;
        return cur_index - offset_index;
    }

    var farthest = [4]usize{0,0,0,0};
    for (indices) |i, index| {
        if (cells[i].depth == 0) break;
        farthest[cells[i].level(begin_depth)] = index+1;
    }

    var last: usize = 0;
    var cur_index = offset_index;
    for (farthest) |qtl, subgroup| {
        if (qtl == 0) continue;
        info.qtls += 1;
        if (qtl - last <= config.node_count_in_one*4) {
            data[cur_index].qtl = .{
                .subgroup=@truncate(u2, subgroup),
                .depth = @truncate(u6, begin_depth),
                .word_size=@truncate(u48, qtl-last),
            };
            const wordsize = &data[cur_index].qtl.word_size;
            const qtl_index = cur_index;

            cur_index += 1;
            //Give the cells references to the current qtl and insert points
            for (indices[last..qtl]) |i| {

                if (cells[i].depth == 0) break;
                info.points += 1;

                cells[i].depth = @truncate(u6, begin_depth+1);
                cells[i].hash = @truncate(u56, qtl_index);
                data[cur_index].point = .{.reference=@truncate(u56, i>>2)};
                cur_index += 1;
            }

            //Make sure only unique references to points exists in one cell
            std.sort.sort(Word, data[qtl_index+1..cur_index], {}, struct {
                pub fn lessThan(_: void, lhs: Word, rhs: Word) bool {
                    return lhs.point.reference < rhs.point.reference;
                }}.lessThan);
            var head: u56 = 0;
            var l: usize = ~@as(usize, 0);
            for (data[qtl_index+1..cur_index]) |p| {
                if (p.point.reference == l) continue;
                l = p.point.reference;
                data[qtl_index+1+head] = p;
                head += 1;
            }
            cur_index = qtl_index+1+head;
            wordsize.* = @truncate(u48, head+1);
        } else {
            const size = buildTreeBranch(config, info, cells, indices[last..qtl], data, begin_depth+1, cur_index+1);
            data[cur_index].qtl = .{
                .subgroup=@truncate(u2, subgroup),
                .depth = @truncate(u6, begin_depth),
                .word_size=@truncate(u48, size),
            };
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
    const t = common.Timer(@src());
    defer Timings.draw = t.end();

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

            cur_hash.hash &= ~((~@as(u56, 0)) >> @truncate(u6, 2*(cur_hash.depth)));
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

            const box_len = std.math.pow(f32, 2, -@intToFloat(f32, cur_hash.depth));
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
        self.config.size.x,    0,                      0,
        0,                      self.config.size.y,   0,
        -self.config.pos.x,    -self.config.pos.y,      1,
    }};

    s.shader.bind();
    s.shader.uniform(camera.getAssembled(), "u_assembled_matrix");
    s.shader.uniform(model_matrix, "u_model_matrix");
    s.vao.drawArrays(.lines, 0, head*2);
}

pub fn print(data: []Word) void {
    var tabs: usize = 0;
    for (data) |word, i| {
        std.debug.print("{}\t|", .{i});
        switch (word.qtl.code) {
            .End => {std.debug.print("End", .{}); break;},
            
            .Level => {
                const qtl = word.qtl;
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
                const point = word.point;
                std.debug.print("Point[index: {}] - ", .{point.reference});
            }
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("\n", .{});
}

const Codes = enum (u8) {
    End     = 0,
    Level   = 1,
    Point   = 2,
};

const Word = packed union {

    qtl: QTL,
    point: Point,
    int: u64,

};

const QTL = packed struct {
    const _size = @sizeOf(@This());

    word_size: u48,
    depth: u6,
    subgroup: u2,
    code: Codes = .Level,
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

    pub fn calc(config: Config, pos: Vec2) Cell {
        if (config.max_depth > MAX_DEPTH) return Cell{.hash=0, .depth=0};
        var xpos = (pos.x - config.pos.x)/config.size.x;
        var ypos = (pos.y - config.pos.y)/config.size.y;

        if (xpos > 1 or xpos < -1 or
            ypos > 1 or ypos < -1) {
            return Cell{.hash=0, .depth=0};
        }

        var cell: Cell = .{.hash=0, .depth=@truncate(u6, config.max_depth)};

        var i: u56 = 0;
        var exp = @as(u56, 1) << 2*(Cell.MAX_DEPTH - 1);
        while (i < config.max_depth) : (i += 1) {
            const x_flag: u56 = if(xpos > 0) 1 else 0;
            const y_flag: u56 = if(ypos > 0) 0 else 1;
            cell.hash |= exp * (x_flag | y_flag << 1);
            exp = exp >> 2;

            xpos = (xpos*2) + (1 - 2.0*@intToFloat(f32, x_flag));
            ypos = (ypos*2) + (1 - 2.0*@intToFloat(f32, 1 - y_flag));
        }

        return cell;
    }

    pub fn print(self: Cell) void {
        var i: usize = 0;
        while (i < self.depth) : (i += 1) {
            std.debug.print("{}", .{self.level(@truncate(u6, i))});
        }
    }

    pub inline fn transform(lvl: u56, sb: u56) u56 {
        return sb << @intCast(u6, 2*(Cell.MAX_DEPTH - lvl - 1));
    }

    pub inline fn set(self: *Cell, l: u64, sb: u64) void {
        if (sb > 3) return;
        if (l >= Cell.MAX_DEPTH) return;
        self.hash &= ~transform(@truncate(u56, l), 3);
        self.hash |= transform(@truncate(u56, l), @truncate(u56, sb));
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
        const cell = tree._cells[i_mj][i_mi];
        var k: u6 = 0;
        while (!(k > Cell.MAX_DEPTH)) : (k += 1) {
            std.debug.print("{}", .{cell.level(k)});
        }
        std.debug.print(" : {}\n", .{tree._cells[i_mj][i_mi].hash});
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
