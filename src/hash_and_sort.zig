const std = @import("std");
const common = @import("common.zig");
const c = @import("c.zig");
const Buffer = @import("buffer.zig").Buffer;
const BufferDescriptor = @import("buffer.zig").BufferDescriptor;
const VertexArray = @import("buffer.zig").VertexArray;
const Shader = @import("shader.zig").Shader;
const QuadTree = @import("quadtree.zig");
const Vec2 = @import("vector.zig").Vec2;
const Allocator = std.mem.Allocator;

const Sorter = struct { 
    hash_shader: Shader = undefined,
    sort_shaders: [5]Shader = undefined,

    pub fn init() Sorter {
        var result: Sorter = undefined;
        result.hash_shader = Shader.initFile("src/point_hash.os") catch unreachable;
        result.sort_shaders[0] = Shader.initFile("src/count_sort_increase_counters.os") catch unreachable;
        result.sort_shaders[1] = Shader.initFile("src/count_sort_assemble1.os") catch unreachable;
        result.sort_shaders[2] = Shader.initFile("src/count_sort_assemble2.os") catch unreachable;
        result.sort_shaders[3] = Shader.initFile("src/count_sort_grouping.os") catch unreachable;
        result.sort_shaders[4] = Shader.initFile("src/count_sort_bucket.os") catch unreachable;
        return result;
    }

    pub fn destroy(self: *Sorter) void {
        self.hash_shader.destroy();
        self.sort_shaders[0].destroy();
        self.sort_shaders[1].destroy();
        self.sort_shaders[2].destroy();
        self.sort_shaders[3].destroy();
        self.sort_shaders[4].destroy();
    }

    pub fn hash(self: Sorter, hashes: BufferDescriptor, points: BufferDescriptor,
                config_size: Vec2, config_pos: Vec2, config_maxdepth: u32) void {

        self.hash_shader.bind();
        points.bind(0, .shader_storage_buffer);
        hashes.bind(1, .shader_storage_buffer);
        self.hash_shader.uniform(config_size, "u_config_size");        
        self.hash_shader.uniform(config_pos, "u_config_pos");        
        self.hash_shader.uniform(config_maxdepth, "u_config_maxdepth");        

        const dispatch_size = @as(u32, 1) + @intCast(u32, points.size/256);
        c.glDispatchCompute(dispatch_size, 1, 1);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);
    }

    pub fn sort(
        self: Sorter, hashes: BufferDescriptor, counter: BufferDescriptor,
        accum: BufferDescriptor, indices: BufferDescriptor) void {
        self.sort_shaders[0].bind();
        hashes.bind(0, .shader_storage_buffer);
        counter.bind(1, .shader_storage_buffer);
        c.glDispatchCompute(4, 4, 4);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.sort_shaders[1].bind();
        counter.bind(0, .shader_storage_buffer);
        accum.bind(1, .shader_storage_buffer);
        c.glDispatchCompute(2, 2, 2);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.sort_shaders[2].bind();
        counter.bind(0, .shader_storage_buffer);
        accum.bind(1, .shader_storage_buffer);
        c.glDispatchCompute(4, 2, 2);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.sort_shaders[3].bind();
        hashes.bind(0, .shader_storage_buffer);
        counter.bind(1, .shader_storage_buffer);
        indices.bind(2, .shader_storage_buffer);
        c.glDispatchCompute(4, 4, 4);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);

        self.sort_shaders[4].bind();
        hashes.bind(0, .shader_storage_buffer);
        counter.bind(1, .shader_storage_buffer);
        indices.bind(2, .shader_storage_buffer);
        c.glDispatchCompute(8, 8, 4);
        c.glMemoryBarrier(c.GL_SHADER_STORAGE_BARRIER_BIT);
    }
};

const HashSort = @This();

general_buffer: Buffer,
general_buffer_head: usize = 0,

index_buffer: Buffer,
hash_buffer: Buffer,
sorter: Sorter,

point_count: usize,

pub fn init() HashSort {

    var result: HashSort = undefined;
    result.general_buffer = Buffer.init(5000000, .dynamic_read);
    result.index_buffer = Buffer.init(5000000, .stream_copy);
    result.hash_buffer = Buffer.init(5000000, .stream_copy);
    std.debug.print("hash_buffer: {}\n", .{result.hash_buffer._buffer_handle});
    result.sorter = Sorter.init();
    result.general_buffer_head = 0;
    
    return result;

}

pub fn destroy(self: *HashSort) void {

    self.general_buffer.destroy();
    self.index_buffer.destroy();
    self.hash_buffer.destroy();
    self.sorter.destroy();

}

pub fn hashAndSort(self: *HashSort, points: []const [2]f32, config: QuadTree.Config) void {
    self.point_count = points.len;
    hash(self, points, config);
    const hashes = self.hash_buffer.range(0, self.point_count * @sizeOf(u64)) catch unreachable;

    const buckets_size: usize = (std.math.powi(usize, 4, 8) catch 0) * @sizeOf(u32);

    self.general_buffer.realloc(buckets_size + 128 * @sizeOf(u32), self.general_buffer.usage);
    const buckets = self.general_buffer.range(0, buckets_size) catch unreachable;
    self.general_buffer.clear(0, buckets_size) catch unreachable;
    const accum = self.general_buffer.range(buckets_size, 128 * @sizeOf(u32)) catch unreachable;

    self.index_buffer.realloc(self.point_count * @sizeOf(u32), self.index_buffer.usage);
    const indices = self.index_buffer.range(0, self.point_count * @sizeOf(u32)) catch unreachable;

    self.sorter.sort(hashes, buckets, accum, indices);
}

fn hash(self: *HashSort, points: []const [2]f32, config: QuadTree.Config) void {
    const points_buffer_size = points.len * @sizeOf([2]f32);

    self.general_buffer.realloc(points_buffer_size + self.general_buffer_head, self.general_buffer.usage);
    self.general_buffer.subData(self.general_buffer_head, 
                                points_buffer_size,
                                common.toData(points)) catch unreachable;
    const point_descriptor = self.general_buffer.range(
        self.general_buffer_head, points_buffer_size) catch unreachable;

    self.hash_buffer.realloc(points.len * @sizeOf(u64), .stream_copy);
    const hash_descriptor = self.hash_buffer.range(0, points.len*@sizeOf(u64)) catch unreachable;

    self.sorter.hash(hash_descriptor, point_descriptor, config.size, config.pos, config.max_depth);
}
 
pub fn updateCpuSize(self: *HashSort, a: Allocator, indices: *[]u32, hashes: *[]u64) void {
    indices.* = a.alloc(u32, self.point_count) catch return;
    hashes.* = a.alloc(u64, self.point_count) catch return;
    self.index_buffer.read(0, self.point_count * @sizeOf(u32), 
        @ptrCast([*]u8, indices.ptr)) catch unreachable;
    self.hash_buffer.read(0, self.point_count * @sizeOf(u64), 
        @ptrCast([*]u8, hashes.ptr)) catch unreachable;
}