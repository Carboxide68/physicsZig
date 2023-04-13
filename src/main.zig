const std = @import("std");
const c = @import("c.zig");
const glfw = @import("glfw");
const renderer = @import("renderer.zig");
const tracy = @import("tracy.zig");
const common = @import("common.zig");
const buffer = @import("buffer.zig");

const Buffer = buffer.Buffer;
const Shader = @import("shader.zig").Shader;
const VertexArray = buffer.VertexArray;
const Camera = @import("Camera.zig");
const QuadTree = @import("quadtree.zig");
const v = @import("vector.zig");
const Vec2 = v.Vec2;
const QTG = @import("quadtree_gpu.zig");

const co_log = std.log.scoped(.co);

const z_p = common.nullPtr;
const render_cam = &renderer.globals.camera;
const glsl_version = "#version 130";
const NotOk = error{NotOk};

var ig_context: *c.ImGuiContext = undefined;

fn glfw_error_callback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.debug.print("GLFW error {}: {s}\n", .{ error_code, description });
}

fn framebuffer_callback(window: glfw.Window, width: u32, height: u32) void {
    _ = window;

    const w = @intCast(i32, width);
    const h = @intCast(i32, height);
    //const max = if (w > h) w else h;
    //c.glViewport(@divFloor(max - w, 2), @divFloor(max - h, 2), w, h);
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
    _ = x;
    _ = window;
    render_cam.zoom(@floatCast(f32, std.math.pow(f64, 1.2, y)));
}

var should_pan = false;
fn glfw_mouse_callback(window: glfw.Window, x: f64, y: f64) void {
    const s = struct {
        var last_xpos: f64 = 0;
        var last_ypos: f64 = 0;
    };
    var x_diff = @floatCast(f32, x - s.last_xpos);
    var y_diff = @floatCast(f32, y - s.last_ypos);
    s.last_xpos = x;
    s.last_ypos = y;

    if (should_pan) {
        const window_size = window.getSize();
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
    _ = mods;
    _ = window;
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
    if (!glfw.init(.{})) {
        co_log.warn("Failed to initialize Glfw!", .{});
    }

    window.* = wndw: {
        var maybe_window = glfw.Window.create(640, 480, "Hello World", null, null, .{
            .context_version_major = 4,
            .context_version_minor = 5,
            .opengl_profile = .opengl_core_profile,
        });
        if (maybe_window) |w| {
            break :wndw w;
        } else {
            co_log.err("Failed to initialize glew!", .{});
            return error.NotOk;
        }
    };

    glfw.makeContextCurrent(window.*);
    window.setFramebufferSizeCallback(framebuffer_callback);
    window.setScrollCallback(glfw_scroll_callback);
    window.setCursorPosCallback(glfw_mouse_callback);
    window.setKeyCallback(glfw_key_callback);
    window.setMouseButtonCallback(glfw_mouse_button_callback);

    glfw.swapInterval(1);

    const err = c.glewInit();
    if (c.GLEW_OK != err) {
        co_log.err("Error: {s}\n", .{c.glewGetErrorString(err)});
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

    render_cam.updateCameraMatrix();

    const direction_data = [8]f32{
        0, 0,
        1, 0,
        0, 0,
        0, 1,
    };
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

    var qt = try QuadTree.init(common.a, .{
        .pos = .{ .x = 0, .y = 0 },
        .size = .{ .x = 10, .y = 10 },
    });
    defer qt.destroy();

    std.debug.print(
        "Timings:\n\tGen: {d:.5}ms\n\tHash: {d:.5}ms\n\tSort: {d:.5}ms\n\tDo Tick: {d:.5}ms\n",
        .{
            @intToFloat(f32, QuadTree.Timings.gen_points) / std.time.ns_per_ms,
            @intToFloat(f32, QuadTree.Timings.hash) / std.time.ns_per_ms,
            @intToFloat(f32, QuadTree.Timings.sort_points) / std.time.ns_per_ms,
            @intToFloat(f32, QuadTree.Timings.do_tick) / std.time.ns_per_ms,
        },
    );
    const POINT_COUNT = 50000;
    var qtg = try QTG.init(common.a, .{});
    defer qtg.destroy();
    qtg.generatePoints(POINT_COUNT);
    var ts: f32 = 0.01;
    var ft: i128 = 0;

    while (!window.shouldClose()) {
        const start = std.time.nanoTimestamp();
        defer ft = std.time.nanoTimestamp() - start;

        c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplGlfw_NewFrame();
        c.igNewFrame();
        c.glClearColor(1.0, 1.0, 1.0, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        if (draw_quadtree) {
            qtg.tick(ts);
        }
        qtg.draw(render_cam.*);

        _ = c.igBegin("Custom Window", 0, 0);
        _ = c.igCheckbox("Show Demo Window", &show_demo_window);

        _ = c.igSliderInt("Ticks per frame", &tick_per_frame, 1, 100, "%d", 0);

        _ = c.igSliderFloat("Tick speed", &ts, 0.001, 1, "%f", 0);

        _ = c.igCheckbox("Toggle Physics", &draw_quadtree);

        _ = c.igText("Frame Time: %f ms", @intToFloat(f32, ft) / 1_000_000);

        if (show_demo_window) {
            c.igShowDemoWindow(&show_demo_window);
        }

        c.igEnd();
        c.igRender();

        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
        window.swapBuffers();

        glfw.pollEvents();
    }
}
