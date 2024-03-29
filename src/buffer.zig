const std = @import("std");
const c = @import("c.zig");
const common = @import("common.zig");

const GLENUM = c_uint;

pub const BufferTarget = enum(GLENUM) {
    atomic_counter = c.GL_ATOMIC_COUNTER_BUFFER,
    transform_feedback = c.GL_TRANSFORM_FEEDBACK_BUFFER,
    uniform = c.GL_UNIFORM_BUFFER,
    shader_storage = c.GL_SHADER_STORAGE_BUFFER,

    _,
    pub fn u(self: BufferTarget) GLENUM {
        return @enumToInt(self);
    }
};

pub const BufferUsage = enum(GLENUM) {
    stream_draw = c.GL_STREAM_DRAW,
    stream_read = c.GL_STREAM_READ,
    stream_copy = c.GL_STREAM_COPY,

    static_draw = c.GL_STATIC_DRAW,
    static_read = c.GL_STATIC_READ,
    static_copy = c.GL_STATIC_COPY,

    dynamic_draw = c.GL_DYNAMIC_DRAW,
    dynamic_read = c.GL_DYNAMIC_READ,
    dynamic_copy = c.GL_DYNAMIC_COPY,

    _,
    pub fn u(self: BufferUsage) GLENUM {
        return @enumToInt(self);
    }
};

pub const GLType = enum(GLENUM) {
    float = c.GL_FLOAT,
    double = c.GL_DOUBLE,

    uint = c.GL_UNSIGNED_INT,
    ushort = c.GL_UNSIGNED_SHORT,

    int = c.GL_INT,
    short = c.GL_SHORT,

    byte = c.GL_UNSIGNED_BYTE,
    _,

    pub fn u(self: GLType) GLENUM {
        return @enumToInt(self);
    }
};

pub const DrawMode = enum(GLENUM) {
    points = c.GL_POINTS,
    line_strip = c.GL_LINE_STRIP,
    line_loop = c.GL_LINE_LOOP,
    lines = c.GL_LINES,
    line_strip_adjacency = c.GL_LINE_STRIP_ADJACENCY,
    triangle_strip = c.GL_TRIANGLE_STRIP,
    triangle_fan = c.GL_TRIANGLE_FAN,
    triangles = c.GL_TRIANGLES,
    triangle_strip_adjacency = c.GL_TRIANGLE_STRIP_ADJACENCY,
    triangles_adjacency = c.GL_TRIANGLES_ADJACENCY,
    patches = c.GL_PATCHES,

    _,

    pub fn u(self: DrawMode) GLENUM {
        return @enumToInt(self);
    }
};

pub const Buffer = struct {
    _buffer_handle: u32 = 0,
    size: u64,
    usage: BufferUsage,

    pub fn init(size: u64, usage: BufferUsage) Buffer {
        var handle: u32 = undefined;
        c.glCreateBuffers(1, &handle);
        if (size != 0)
            c.glNamedBufferData(
                handle,
                @bitCast(i64, size),
                common.nullPtr(anyopaque),
                usage.u(),
            );
        return Buffer{ ._buffer_handle = handle, .size = size, .usage = usage };
    }

    pub fn destroy(self: *Buffer) void {
        c.glDeleteBuffers(1, &self._buffer_handle);
        self._buffer_handle = 0;
    }

    pub fn realloc(self: *Buffer, size: u64, usage: BufferUsage) void {
        if (size <= self.size and usage == self.usage) return;
        c.glNamedBufferData(
            self._buffer_handle,
            @intCast(i64, size),
            common.nullPtr(anyopaque),
            usage.u(),
        );
        self.size = size;
        self.usage = usage;
    }

    pub fn subData(self: Buffer, offset: u64, size: u64, data: anytype) !void {
        if (offset + size > self.size) return error.InvalidAccess;
        c.glNamedBufferSubData(
            self._buffer_handle,
            @bitCast(i64, offset),
            @bitCast(i64, size),
            @ptrCast(*const anyopaque, &data[0]),
        );
    }

    pub fn read(self: Buffer, offset: usize, size: usize, out: [*]u8) !void {
        if (@intCast(u64, offset) + @intCast(u64, size) > self.size) return error.InvalidAccess;
        c.glGetNamedBufferSubData(
            self._buffer_handle,
            @intCast(c_longlong, offset),
            @intCast(isize, size),
            common.voidPtr(out),
        );
    }

    const NotAligned = error{};

    pub fn readT(self: Buffer, T: type, offset: usize, size: usize, out: [*]T) !void {
        if (@intCast(u64, offset) + @intCast(u64, size) > self.size) return error.InvalidAccess;
        if (size % @sizeOf(T) != 0) return NotAligned;
        c.glGetNamedBufferSubData(
            self._buffer_handle,
            @intCast(c_longlong, offset),
            @intCast(isize, size),
            common.voidPtr(out),
        );
    }

    pub fn bindRange(self: Buffer, target: BufferTarget, index: usize, offset: usize, size: usize) !void {
        if (@intCast(u64, offset) + @intCast(u64, size) > self.size) return error.InvalidAccess;
        c.glBindBufferRange(
            target.u(),
            @intCast(u32, index),
            self._buffer_handle,
            @intCast(isize, offset),
            @intCast(isize, size),
        );
    }

    pub fn bindAll(self: Buffer, target: BufferTarget, index: usize) !void {
        try self.bindRange(
            target,
            index,
            0,
            self.size,
        );
    }

    pub fn range(self: *Buffer, start: usize, size: usize) !BufferDescriptor {
        if (@intCast(u64, start) + @intCast(u64, size) > self.size) return error.InvalidAccess;
        return BufferDescriptor{
            .buffer = self,
            .start = start,
            .size = size,
        };
    }

    pub fn clear(self: *Buffer, offset: usize, size: usize) !void {
        if (@intCast(u64, offset) + @intCast(u64, size) > self.size) return error.InvalidAccess;
        c.glClearNamedBufferSubData(
            self._buffer_handle,
            c.GL_RGBA8,
            @intCast(c_longlong, offset),
            @intCast(isize, size),
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            common.nullPtr(anyopaque),
        );
    }
};

pub const BufferDescriptor = struct {
    buffer: *Buffer,
    start: usize,
    size: usize,

    pub fn bind(self: BufferDescriptor, index: usize, target: BufferTarget) void {
        self.buffer.bindRange(
            target,
            index,
            self.start,
            self.size,
        ) catch {};
    }

    pub fn read(self: BufferDescriptor, buffer: [*]u8) void {
        self.buffer.read(
            self.start,
            self.size,
            buffer,
        );
    }
};

pub const VertexArray = struct {
    _handle: u32,

    pub fn init() VertexArray {
        var handle: u32 = undefined;
        c.glCreateVertexArrays(1, &handle);
        return .{ ._handle = handle };
    }

    pub fn destroy(self: *VertexArray) void {
        c.glDeleteVertexArrays(1, &self._handle);
        self._handle = 0;
    }

    pub fn bind(self: VertexArray) void {
        c.glBindVertexArray(self._handle);
    }

    pub inline fn drawElements(self: VertexArray, mode: DrawMode, offset: u64, count: u64, index_type: GLType) void {
        self.bind();
        c.glDrawElements(
            mode.u(),
            @bitCast(i64, count),
            index_type.u(),
            common.voidPtr(offset),
        );
    }

    pub inline fn drawElementsInstanced(self: VertexArray, mode: DrawMode, offset: u64, count: u64, instance_count: u32, index_type: GLType) void {
        self.bind();
        c.glDrawElementsInstanced(
            mode.u(),
            @bitCast(i64, count),
            index_type.u(),
            common.voidPtr(offset),
            instance_count,
        );
    }

    pub inline fn drawArrays(self: VertexArray, mode: DrawMode, offset: u32, count: u32) void {
        self.bind();
        c.glDrawArrays(
            mode.u(),
            @bitCast(i32, offset),
            @bitCast(i32, count),
        );
    }

    pub inline fn drawArraysInstanced(self: VertexArray, mode: DrawMode, offset: u32, count: u32, instance_count: u32) void {
        self.bind();
        c.glDrawArraysInstanced(
            mode.u(),
            @bitCast(i32, offset),
            @bitCast(i32, count),
            @bitCast(i32, instance_count),
        );
    }

    pub fn bindVertexBuffer(self: VertexArray, buffer: Buffer, vb_index: u32, offset: u64, stride: u32) void {
        self.bind();
        c.glVertexArrayVertexBuffer(
            self._handle,
            vb_index,
            buffer._buffer_handle,
            @bitCast(i64, offset),
            @bitCast(i32, stride),
        );
    }

    pub fn bindIndexBuffer(self: VertexArray, buffer: Buffer) void {
        c.glVertexArrayElementBuffer(
            self._handle,
            buffer._buffer_handle,
        );
    }

    pub fn setLayout(self: VertexArray, attr_index: u32, count: u32, vertex_offset: u32, t: GLType) void {
        c.glEnableVertexArrayAttrib(self._handle, attr_index);

        c.glVertexArrayAttribFormat(
            self._handle,
            attr_index,
            @bitCast(i32, count),
            t.u(),
            c.GL_FALSE,
            vertex_offset,
        );
    }
};
