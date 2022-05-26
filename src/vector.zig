const std = @import("std");
const math = std.math;

pub const Vec2 = Vec2T(f32);
pub const Vec3 = Vec3T(f32);
pub const Vec4 = Vec4T(f32);
pub const Mat2 = Mat2T(f32);
pub const Mat3 = Mat3T(f32);
pub const Mat4 = Mat4T(f32);

const USE_SIMD_MATH = true;

///This vector library is bad
///All matrix types are row-major

inline fn dotProductGeneral(comptime L: comptime_int, comptime T: type, lhs: [L]T, rhs: [L]T) T {
    if (USE_SIMD_MATH) {
        const v_lhs: @Vector(L, T) = lhs;
        const v_rhs: @Vector(L, T) = rhs;

        return @reduce(.Add, v_lhs * v_rhs);
    } else {
        var result = @as(T, 0);
        for (lhs) |_, i| {
            result += lhs[i] * rhs[i];
        }
        return result;
    }
}

inline fn multScalar(comptime L: comptime_int, comptime T: type, lhs: *[L]T, scalar: T) void {
    for (lhs) |*c| {
        c.* *= scalar;
    }
}

pub fn Vec2T(comptime T: type) type {
    return packed struct {
        const _len = 2;
        const This = @This();

        x: T align(@alignOf([_len]T)),
        y: T,

        pub fn init(val: T) This {
            return .{.x=val, .y=val};
        }

        pub fn gen(x: T, y: T) This {
            return .{.x=x, .y=y};
        }

        pub fn dot(lhs: This, rhs: This) T {
            return dotProductGeneral(_len, T, lhs.dataC().*, rhs.dataC().*);
        }

        pub fn add(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x + rhs.x,
                .y = lhs.y + rhs.y,
            };
        }

        pub fn sub(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x - rhs.x,
                .y = lhs.y - rhs.y,
            };
        }

        pub fn mult(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x * rhs.x,
                .y = lhs.y * rhs.y,
            };
        }

        pub fn sMult(lhs: This, rhs: T) This {
            return .{
                .x = lhs.x * rhs,
                .y = lhs.y * rhs,
            };
        }

        pub fn length(self: This) T {
            return math.sqrt(self.length2());
        }

        pub fn length2(self: This) T {
            return dot(self, self);
        }

        pub fn normalize(self: This) This {
            return self.sMult(1/self.length());
        }

        pub fn data(self: *This) *[_len]T {
            return @ptrCast(*[_len]T, self);
        }

        pub fn dataC(self: *const This) *const [_len]T {
            return @ptrCast(*const [_len]T, self);
        }
    };
}

pub fn Vec3T(comptime T: type) type {
    return packed struct {
        const _len = 3;
        const This = @This();

        x: T align(@alignOf([_len]T)),
        y: T,
        z: T,

        pub fn init(val: T) This {
            return .{.x=val, .y=val, .z=val};
        }

        pub fn gen(x: T, y: T, z: T) This {
            return .{.x=x, .y=y, .z=z};
        }

        pub fn dot(lhs: This, rhs: This) T {
            return dotProductGeneral(_len, T, lhs.dataC().*, rhs.dataC().*);
        }

        pub fn add(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x + rhs.x,
                .y = lhs.y + rhs.y,
                .z = lhs.z + rhs.z,
            };
        }

        pub fn sub(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x - rhs.x,
                .y = lhs.y - rhs.y,
                .z = lhs.z - rhs.z,
            };
        }

        pub fn mult(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x * rhs.x,
                .y = lhs.y * rhs.y,
                .z = lhs.z * rhs.z,
            };
        }

        pub fn sMult(lhs: This, rhs: T) This {
            return .{
                .x = lhs.x * rhs,
                .y = lhs.y * rhs,
                .z = lhs.z * rhs,
            };
        }

        pub fn length(self: This) T {
            return math.sqrt(self.length2());
        }

        pub fn length2(self: This) T {
            return dot(self, self);
        }

        pub fn normalize(self: This) This {
            return self.sMult(1/self.length());
        }

        pub fn data(self: This) *[_len]T {
            return @ptrCast(*[_len]T, self);
        }

        pub fn dataC(self: *const This) *const [_len]T {
            return @ptrCast(*const [_len]T, self);
        }
    };
}
pub fn Vec4T(comptime T: type) type {
    return packed struct {
        const _len = 4;
        const This = @This();

        x: T align(@alignOf([_len]T)),
        y: T,
        z: T,
        w: T,

        pub fn init(val: T) This {
            return .{.x=val, .y=val, .z=val, .w=val};
        }

        pub fn gen(x: T, y: T, z: T, w: T) This {
            return .{.x=x, .y=y, .z=z, .w=w};
        }

        pub fn dot(lhs: This, rhs: This) T {
            return dotProductGeneral(_len, T, lhs.dataC().*, rhs.dataC().*);
        }

        pub fn add(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x + rhs.x,
                .y = lhs.y + rhs.y,
                .z = lhs.z + rhs.z,
                .w = lhs.w + rhs.w,
            };
        }

        pub fn sub(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x - rhs.x,
                .y = lhs.y - rhs.y,
                .z = lhs.z - rhs.z,
                .w = lhs.w - rhs.w,
            };
        }

        pub fn mult(lhs: This, rhs: This) This {
            return .{
                .x = lhs.x * rhs.x,
                .y = lhs.y * rhs.y,
                .z = lhs.z * rhs.z,
                .w = lhs.w * rhs.w,
            };
        }

        pub fn sMult(lhs: This, rhs: T) This {
            return .{
                .x = lhs.x * rhs,
                .y = lhs.y * rhs,
                .z = lhs.z * rhs,
                .w = lhs.w * rhs,
            };
        }

        pub fn length(self: This) T {
            return math.sqrt(self.length2());
        }

        pub fn length2(self: This) T {
            return dot(self, self);
        }

        pub fn normalize(self: This) This {
            return self.sMult(1/self.length());
        }

        pub fn data(self: *This) *[_len]T {
            return @ptrCast(*[_len]T, self);
        }

        pub fn dataC(self: *const This) *const [_len]T {
            return @ptrCast(*const [_len]T, self);
        }
    };
}

pub fn Mat2T(comptime T: type) type {
    return packed struct {
        const _len = 4;
        const _row = math.sqrt(_len);
        const This = @This();

        data: [_len]T,

        pub fn init(val: T) This {
            return .{.data=[_]T{
                val, 0  ,
                0  , val,
            }};
        }

        pub fn mMult(lhs: This, rhs: This) This {
            var new: [_len]T = [_]T{0}**_len;
            for (new) |*c, i| {
                const row = i&1;
                const column = @divFloor(i, _row)*_row;
                c.* += lhs.data[row + (0)*_row] * rhs.data[(0) + column];
                c.* += lhs.data[row + (1)*_row] * rhs.data[(1) + column];
                c.* += lhs.data[row + (2)*_row] * rhs.data[(2) + column];
            }
            return .{.data=new};
        }

        pub fn vMult(lhs: This, rhs: Vec2T(T)) Vec2T(T) {
            var new: Vec2T(T) = Vec2T(T).init(0);
            const rhs_d: *const[_row]T = rhs.dataC();
            const d = new.data();
            for (d) |*c, i| {
                c.* += lhs.data[0 + i*_row] * rhs_d[0];
                c.* += lhs.data[1 + i*_row] * rhs_d[1];
            }
            return new;
        }

        pub fn sMult(lhs: This, rhs: T) This {
            var new: This = undefined;
            for (new.data) |*c, i| {
                c.* = lhs.data[i] * rhs;
            }
            return new;
        }

        pub fn transpose(self: This) This {
            const new: This = undefined;
            for (new.data) |*c, i| {
                c.* = self.data[@divFloor(i, _row) + (i%_row)*_row];
            }
            return new;
        }
    };
}

pub fn Mat3T(comptime T: type) type {
    return struct {
        const _len = 9;
        const _row = math.sqrt(_len);
        const This = @This();

        data: [_len]T,

        pub fn init(val: T) This {
            return .{.data=[_]T{
                val ,   0   ,   0   ,
                0   ,   val ,   0   ,
                0   ,   0   ,   val ,
            }};
        }

        pub fn mMult(lhs: This, rhs: This) This {
            var new: [_len]T = [_]T{0}**_len;
            for (new) |*c, i| {
                const row = i%3;
                const column = @divFloor(i, _row)*_row;
                c.* += lhs.data[row + (0)*_row] * rhs.data[(0) + column];
                c.* += lhs.data[row + (1)*_row] * rhs.data[(1) + column];
                c.* += lhs.data[row + (2)*_row] * rhs.data[(2) + column];
            }
            return .{.data=new};
        }

        pub fn vMult(lhs: This, rhs: Vec3T(T)) Vec3T(T) {
            var new: Vec3T(T) = Vec3T(T).init(0);
            const rhs_d: *const[_row]T = rhs.dataC();
            const d = new.data();
            for (d) |*c, i| {
                c.* += lhs.data[0 + i*_row] * rhs_d[0];
                c.* += lhs.data[1 + i*_row] * rhs_d[1];
                c.* += lhs.data[2 + i*_row] * rhs_d[2];
            }
            return new;
        }

        pub fn sMult(lhs: This, rhs: T) This {
            var new: This = undefined;
            for (new.data) |*c, i| {
                c.* = lhs[i] * rhs;
            }
            return new;
        }

        pub fn transpose(self: This) This {
            const new: This = undefined;
            for (new.data) |*c, i| {
                c.* = self.data[@divFloor(i, _row) + (i%_row)*_row];
            }
            return new;
        }
    };
}

pub fn Mat4T(comptime T: type) type {
    return struct {
        const _len = 16;
        const _row = math.sqrt(_len);
        const This = @This();

        data: [_len]T,

        pub fn init(val: T) This {
            return .{.data=[_]T{
                val ,   0   ,   0   ,   0   ,
                0   ,   val ,   0   ,   0   ,
                0   ,   0   ,   val ,   0   ,
                0   ,   0   ,   0   ,   val ,
            }};
        }

        pub fn mMult(lhs: This, rhs: This) This {
            var new: [_len]T = [_]T{0}**_len;
            for (new) |*c, i| {
                const row = i&3;
                const column = @divFloor(i, _row)*_row;
                c.* += lhs.data[row + (0)*_row] * rhs.data[(0) + column];
                c.* += lhs.data[row + (1)*_row] * rhs.data[(1) + column];
                c.* += lhs.data[row + (2)*_row] * rhs.data[(2) + column];
                c.* += lhs.data[row + (3)*_row] * rhs.data[(3) + column];
            }
            return .{.data=new};
        }

        pub fn vMult(lhs: This, rhs: Vec4T(T)) Vec4T(T) {
            var new: Vec4T(T) = Vec4T(T).init(0);
            const rhs_d: *const[_row]T = rhs.dataC();
            const d = new.data();
            for (d) |*c, i| {
                c.* += lhs.data[0 + i*_row] * rhs_d[0];
                c.* += lhs.data[1 + i*_row] * rhs_d[1];
                c.* += lhs.data[2 + i*_row] * rhs_d[2];
                c.* += lhs.data[3 + i*_row] * rhs_d[3];
            }
            return new;
        }

        pub fn sMult(lhs: This, rhs: T) This {
            var new: This = undefined;
            for (new.data) |*c, i| {
                c.* = lhs[i] * rhs;
            }
            return new;
        }

        pub fn transpose(self: This) This {
            var new: This = undefined;
            for (new.data) |*c, i| {
                c.* = self.data[@divFloor(i, _row) + (i%_row)*_row];
            }
            return new;
        }
    };
}

pub fn printMatrix(mat: anytype) void {
    const Mat = @TypeOf(mat);
    var k: usize = 0;
    while (k < Mat._row) : (k += 1) {
        var j: usize = 0;
        std.debug.print("| ", .{});
        while (j < Mat._row) : (j += 1) {
            std.debug.print("{} ", .{mat.data[k*Mat._row+j]});
        }
        std.debug.print("|\n", .{});
    }
}

test "Everything" {

    const a = Mat4{.data=[16]f32{
        5, 8, 3, 8,
        7, 9, 1, 2,
        2, 5, 4, 1,
        1, 7, 4, 9,
    }};

    std.debug.print("row2: {} | row3: {} | row4: {}\n", .{Mat2._row, Mat3._row, Mat4._row});
    printMatrix(a);
    std.debug.print("\n", .{});
    printMatrix(a.transpose());

}
