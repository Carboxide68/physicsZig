const std = @import("std");
const c = @import("c.zig");

const heap = std.heap;

pub var general_allocator: heap.GeneralPurposeAllocator(.{}) = .{};
pub var a: std.mem.Allocator = general_allocator.allocator();

pub fn nullPtr(comptime T: type) *allowzero T {

    return @intToPtr(*allowzero T, 0);

}

//Potentially might leak data if input variable is not a 64 bit type
pub fn voidPtr(input: anytype) *allowzero anyopaque {
    return @ptrCast(*allowzero anyopaque, input);
}

pub fn toData(data: anytype) [*]const u8 {

    return @ptrCast([*]const u8, data);

}

pub const Time = struct {
    now: i128,
    src: std.builtin.SourceLocation,

    pub fn end(self: Time) i128 {
        return (std.time.nanoTimestamp() - self.now);
    }
    pub fn endPrint(self: Time) i128 {
        const tdiff = (std.time.nanoTimestamp() - self.now);
        std.debug.print("Time passed in function {s}: {}ms\n", .{self.src.fn_name, @divFloor(tdiff, 1000000)});
        return tdiff;
    }
};

pub fn timer(src: std.builtin.SourceLocation) Time {
    return Time{.src=src, .now = std.time.nanoTimestamp()};
}

pub fn imButton(text: [:0]const u8) bool {
    var text_size: c.ImVec2 = undefined;
    if (text.len == 0) {
        text_size = c.ImVec2{.x=0, .y=0};
    } else {
        c.igCalcTextSize(&text_size, text.ptr, &text[text.len], true, 1000.0);
    }
    text_size.x += 8;
    text_size.y += 8;
    return c.igButton(text, text_size);
}