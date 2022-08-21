const std = @import("std");
const c = @import("c.zig");
const glfw = @import("glfw");
const renderer = @import("renderer.zig");
const render_cam = &renderer.globals.camera;
const HashSort = @import("hash_and_sort.zig");

const common = @import("common.zig");
const z_p = common.nullPtr;
const buffer = @import("buffer.zig");
const Buffer = buffer.Buffer;
const Shader = @import("shader.zig").Shader;
const VertexArray = buffer.VertexArray;
const VoidBuffer = @import("voidbuffer.zig");
const Camera = @import("camera.zig");
const QuadTree = @import("quadtree.zig");
const Engine = @import("engine.zig");
const v = @import("vector.zig");
const Vec2 = v.Vec2;

const glsl_version = "#version 130";

var ig_context: *c.ImGuiContext = undefined;

fn glfw_error_callback(error_code: glfw.Error, description: [:0]const u8) void {
    std.debug.print("GLFW error {}: {s}\n", .{ error_code, description });
}

fn framebuffer_callback(window: glfw.Window, width: u32, height: u32) void {
    _ = window;

    const w = @intCast(i32, width);
    const h = @intCast(i32, height);
    c.glViewport(0, 0, w, h);

    render_cam.updateCameraMatrix();
}

fn opengl_error_callback(source: c.GLenum, error_type: c.GLenum, id: c.GLuint, severity: c.GLenum, length: c.GLsizei, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
    const m = message[0..@intCast(usize, length)];
    _ = id;
    _ = source;
    _ = error_type;
    if (severity == c.GL_DEBUG_SEVERITY_HIGH) {
        std.debug.print("OpenGL Error! | Severity: High | {s}\n", .{m});
    }
}

fn glfw_scroll_callback(window: glfw.Window, x: f64, y: f64) void {
    _ = window;
    _ = y;
    _ = x;
    render_cam.zoom(@floatCast(f32, std.math.pow(f64, 1.2, y)));
}

var should_pan = false;
fn glfw_mouse_callback(window: glfw.Window, x: f64, y: f64) void {
    const s = struct {
        var last_xpos: f64 = 0;
        var last_ypos: f64 = 0;
    };
    _ = window;
    _ = x;
    _ = y;
    var x_diff = @floatCast(f32, x - s.last_xpos);
    var y_diff = @floatCast(f32, y - s.last_ypos);
    s.last_xpos = x;
    s.last_ypos = y;

    if (should_pan) {
        const window_size = window.getSize() catch return;
        const fwidth = @intToFloat(f32, window_size.width);
        const fheight = @intToFloat(f32, window_size.height);
        const x_p: f32 = -2 * x_diff / fwidth;
        const y_p: f32 = 2 * y_diff / fheight;

        const matrix = render_cam.getAssembled();
        const cam_x = Vec2.gen(matrix.data[0], matrix.data[1]);
        const cam_y = Vec2.gen(matrix.data[3], matrix.data[4]);
        const move_x = cam_x.sMult(x_p / cam_x.length());
        const move_y = cam_y.sMult(y_p / cam_y.length());
        render_cam.move(move_x.x + move_y.x, move_x.y + move_y.y);
    }
}

fn glfw_key_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = window;
    _ = key;
    _ = scancode;
    _ = action;
    _ = mods;
}

fn glfw_mouse_button_callback(window: glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) void {
    _ = window;
    _ = button;
    _ = action;
    _ = mods;
    switch (button) {
        .left => {
            if (action == .press) {
                should_pan = true;
            } else if (action == .release) {
                should_pan = false;
            }
        },

        else => {},
    }
}

fn glInit(window: *glfw.Window) !void {
    glfw.setErrorCallback(glfw_error_callback);
    try glfw.init(.{});

    window.* = try glfw.Window.create(640, 480, "Hello World", null, null, .{
        .context_version_major = 4,
        .context_version_minor = 5,
        .opengl_profile = .opengl_core_profile,
    });
    try glfw.makeContextCurrent(window.*);
    window.setFramebufferSizeCallback(framebuffer_callback);
    window.setScrollCallback(glfw_scroll_callback);
    window.setCursorPosCallback(glfw_mouse_callback);
    window.setKeyCallback(glfw_key_callback);
    window.setMouseButtonCallback(glfw_mouse_button_callback);

    glfw.swapInterval(1.0) catch unreachable;

    const err = c.glewInit();
    if (c.GLEW_OK != err) {
        std.debug.print("Error: {s}\n", .{c.glewGetErrorString(err)});
        return error.Error;
    }

    c.glDebugMessageCallback(opengl_error_callback, z_p(anyopaque));
    c.glEnable(c.GL_DEBUG_OUTPUT);
    if (@import("builtin").mode == .Debug) {
        c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
    }

    //c.glEnable(c.GL_DEPTH_TEST);

    ig_context = c.igCreateContext(null);
    if (!c.ImGui_ImplGlfw_InitForOpenGL(@ptrCast(*c.GLFWwindow, window.handle), true)) {
        std.debug.panic("", .{});
    }

    if (!c.ImGui_ImplOpenGL3_Init(glsl_version)) {
        std.debug.panic("Could not init opengl", .{});
        return error.InvalidValue;
    }
}

fn glDeinit(window: *glfw.Window) void {
    c.ImGui_ImplOpenGL3_Shutdown();
    c.ImGui_ImplGlfw_Shutdown();
    c.igDestroyContext(ig_context);

    window.destroy();
    glfw.terminate();
}

pub fn main() anyerror!void {
    var window = &renderer.globals.window;

    try glInit(window);
    defer glDeinit(window);

    c.glClearColor(0.3, 0.3, 0, 1);

    var engine = Engine.init(common.a, .{});
    defer engine.destroy();

    //var hs: HashSort = HashSort.init();
    //defer hs.destroy();
    
    //const seed = 9;
    //var mesa = std.rand.DefaultPrng.init(seed);
    //var prng = mesa.random();

    //const node_count = 100000;
    //const config = QuadTree.Config{
    //    .pos=.{.x=0, .y=0},
    //    .size=.{.x=10, .y=10},
    //};
    //const b = config.size;
    //var positions: [node_count][2]f32 = undefined;

    //for (positions[0..]) |*pos| {
    //    const r = config.point_radius;
    //    pos[0] = (b.x - r) * (prng.float(f32) * 2 - 1);
    //    pos[1] = (b.y - r) * (prng.float(f32) * 2 - 1);
    //}

    //hs.hashAndSort(positions[0..], config);
    //var indices: []u32 = undefined;
    //var hashes: []u64 = undefined;
    //hs.updateCpuSize(common.a, &indices, &hashes);
    //defer common.a.free(hashes);
    //defer common.a.free(indices);

    //for (indices) |index, i| {
    //    const hash = hashes[index];
    //    std.debug.print("{}:  \t{}  \t{}\n", .{i, hash >> 48, hash});
    //}

    render_cam.updateCameraMatrix();

    const direction_data = [8]f32{
        0, 0,
        1, 0,
        0, 0,
        0, 1,
    };
    var direction_pos = Vec2{ .x = -0.9, .y = -0.9 };
    var dir_vao = VertexArray.init();
    defer dir_vao.destroy();

    var dir_buffer = Buffer.init(@sizeOf(f32) * direction_data.len, .static_draw);
    defer dir_buffer.destroy();

    try dir_buffer.subData(0, @sizeOf(f32) * direction_data.len, common.toData(&direction_data[0]));
    dir_vao.bindVertexBuffer(dir_buffer, 0, 0, @sizeOf(f32) * 2);
    dir_vao.setLayout(0, 2, 0, buffer.GLType.float);

    const dir_shader = try Shader.initFile("src/dir_shader.os");
    defer dir_shader.destroy();

    var show_demo_window: bool = false;
    var draw_quadtree: bool = false;
    var tick_per_frame: i32 = 1;

    while (!window.shouldClose()) {
        c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplGlfw_NewFrame();
        c.igNewFrame();

        c.glClearColor(1.0, 1.0, 1.0, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        _ = c.igBegin("Custom Window", 0, 0);
        _ = c.igCheckbox("Show Demo Window", &show_demo_window);

        if (draw_quadtree) {
            var i: u32 = 0;
            while (i < tick_per_frame) : (i += 1) {
                engine.doTick();
            }
        }

        engine.draw(render_cam.*);

        dir_shader.bind();
        dir_shader.uniform(direction_pos, "u_position");
        dir_shader.uniform(render_cam.getAssembled(), "u_camera_matrix");
        dir_vao.drawArrays(.lines, 0, 4);
        
        _ = c.igInputFloat2("Lines", &direction_pos.x, "%.3f", 0);
        _ = c.igSliderInt("Ticks per frame", &tick_per_frame, 1, 100, "%d", 0);
        _ = c.igSliderInt("Nodes In One", @ptrCast([*c]c_int, &engine.qt.config.node_count_in_one), 1, 18, "%d", 0);

        _ = c.igCheckbox("Toggle Physics", &draw_quadtree);
        if (common.imButton("Draw quadtree")) {
            engine.doTick();
        }

        if (show_demo_window) {
            c.igShowDemoWindow(&show_demo_window);
        }

        c.igEnd();
        c.igRender();

        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());

        if (window.swapBuffers()) {} else |err| {
            std.debug.panic("failed to swap buffers: {}", .{err});
        }

        try glfw.pollEvents();
    }
}
