const std = @import("std");
const stbi = @import("stb_image.zig");
const common = @import("common.zig");

const Texture = struct {

    x: u32,
    y: u32,
    channels: u32,
    data: ?[][4]u8,

    _handle: ?u32,

    pub fn load_image(file_path: [:0]const u8) Texture {
    
        

    }

    pub fn gpuLoad() void {
    
        

    }

    pub fn destroy() void {
        if (data) |d| {
            stbi.STBI_FREE(d);
        }
        
        if (_handle) |h| {
            glDeleteTextures(1, &h);
        }
    }

}
