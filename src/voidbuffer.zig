const std = @import("std");
const common = @import("common.zig");

const VoidBuffer = @This();

const Interval = struct {
    begin: u64,
    end: u64,
};

const array_error = error{
    OutOfBounds,
};

_a: *std.mem.Allocator,
ptr: []u8,
head: usize,
size: usize,
labels: std.AutoHashMap([16]u8, Interval),

pub fn init(size: usize, a: *std.mem.Allocator) !VoidBuffer {
    var vb: VoidBuffer = undefined;
    vb._a = a;
    vb.labels = std.AutoHashMap([16]u8, Interval).init(a.*);
    vb.ptr = try a.alloc(u8, size);
    vb.size = size;
    vb.head = 0;
    return vb;
}

pub fn destroy(self: *VoidBuffer) void {
    self.labels.deinit();
    self._a.free(self.ptr);
}

pub fn add(self: *VoidBuffer, val: anytype) !void {
    const T = @TypeOf(val);
    const size = @sizeOf(T);
    const alignment = @alignOf(T);
    const aa = alignment - (@mod(size, alignment));

    if (size + self.head + aa > self.size) return array_error.OutOfBounds;

    const val_ptr = @intToPtr(*T, @ptrToInt(&self.ptr[self.head + aa]));
    val_ptr.* = val;
    self.head += size;
}

pub fn get(self: VoidBuffer, comptime T: type, byte_pos: usize) !T {
    if (byte_pos > self.size) return array_error.OutOfBounds;

    const val = @bitCast(T, self.ptr[byte_pos]);
    return val;
}

pub fn begin(self: *VoidBuffer, label: []u8) void {
    var l: [16]u8 = undefined;
    for (label, 0..) |char, i| {
        if (i == 16) break;
        l[i] = char;
    }
    self.labels.put(l, .{ self.head, self.head });
}

pub fn end(self: *VoidBuffer, label: []u8) void {
    var l: [16]u8 = undefined;
    for (label, 0..) |char, i| {
        if (i == 16) break;
        l[i] = char;
    }
    const val = self.labels.getPtr(label);
    if (val) |v| {
        v.end = self.head;
    } else return;
}
