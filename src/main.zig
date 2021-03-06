const std = @import("std");
const c = @import("c.zig");
const glfw = @import("glfw");
const common = @import("common.zig");
const z_p = common.nullPtr;
const buffer = @import("buffer.zig");
const Buffer = buffer.Buffer;
const Shader = @import("shader.zig").Shader;
const VertexArray = buffer.VertexArray;
const VoidBuffer = @import("voidbuffer.zig");
const Camera = @import("camera.zig");
const QuadTree = @import("quadtree.zig");
const v = @import("vector.zig");
const Vec2 = v.Vec2;

const glsl_version = "#version 130";

var ig_context: *c.ImGuiContext = undefined;

const circle_polygon_size = 32;
const circle_vertex_data = blk: {
    var data: [circle_polygon_size + 1][2]f32 = undefined;
    data[0] = .{ 0.0, 0.0 };

    for (data[1..]) |*poly, i| {
        const fi = @intToFloat(f32, i);
        const fi2 = @intToFloat(f32, circle_polygon_size - 1);
        const angle: f32 = std.math.pi * 2.0 * fi / fi2;
        poly.* = .{ std.math.cos(angle), std.math.sin(angle) };
    }
    break :blk data;
};

var myCamera: Camera = undefined;

fn glfw_error_callback(error_code: glfw.Error, description: [:0]const u8) void {
    std.debug.print("GLFW error {}: {s}\n", .{error_code, description});
}

fn framebuffer_callback(window: glfw.Window, width: u32, height: u32) void {
    _ = window;

    const w = @intCast(i32, width);
    const h = @intCast(i32, height);
    c.glViewport(0, 0, w, h);

    myCamera.updateCameraMatrix();
}

fn opengl_error_callback(source: c.GLenum, error_type: c.GLenum, 
                        id: c.GLuint, severity: c.GLenum, 
                        length: c.GLsizei, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
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
    myCamera.zoom(@floatCast(f32, std.math.pow(f64, 1.2, y)));
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
        const x_p: f32 = -2 * x_diff/fwidth;
        const y_p: f32 = 2 * y_diff/fheight;

        const cam_x = Vec2.gen(myCamera.view_matrix.data[0], myCamera.view_matrix.data[1]);
        const cam_y = Vec2.gen(myCamera.view_matrix.data[3], myCamera.view_matrix.data[4]);
        const move_x = cam_x.sMult(x_p/cam_x.length());
        const move_y = cam_y.sMult(y_p/cam_y.length());
        myCamera.move(move_x.x + move_y.x, move_x.y + move_y.y);
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
        
    var window = &common.window;

    try glInit(window);
    defer glDeinit(window);

    c.glClearColor(0.3, 0.3, 0, 1);

    var my_VAO = buffer.VertexArray.init();
    defer my_VAO.destroy();

    var vertex_buffer = Buffer.init(@sizeOf(f32) * 2 * circle_vertex_data.len, .static_draw);
    defer vertex_buffer.destroy();

    const seed = 9;
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();
    const node_count: usize = 20000;
    const width: f32 = 5;
    const height: f32 = 5;
    var nodes: [node_count][2]f32 = undefined;
    for (nodes) |*node| {
        node[0] = (rand.float(f32) * 2 - 1) * width;
        node[1] = (rand.float(f32) * 2 - 1) * height;
    }

    const radius: f32 = 0.02;

    var node_buffer = Buffer.init(@sizeOf([2]f32) * node_count, .stream_draw);
    try node_buffer.bindRange(.shader_storage_buffer, 0, 0, @intCast(i64, node_buffer.size));
    try node_buffer.subData(0, node_buffer.size, common.toData(&nodes[0]));

    try vertex_buffer.subData(0, @sizeOf(f32) * 2 * circle_vertex_data.len, common.toData(&circle_vertex_data));

    var qt = QuadTree.init(common.a, 20, [2]f32{0, 0}, width*2, height*2);
    qt.config.point_radius = radius;
    qt.build(nodes[0..]);
    qt.build(nodes[0..]);
    qt.build(nodes[0..]);

    my_VAO.bindVertexBuffer(vertex_buffer, 0, 0, 8);
    my_VAO.setLayout(0, 2, 0, buffer.GLType.float);
    const my_shader = try Shader.initFile("src/circle_shader.os");
    defer my_shader.destroy();

    myCamera = Camera.init();
    myCamera.setZoom(0.5);

    var show_demo_window: bool = false;
    var draw_quadtree: bool = true;
    while (!window.shouldClose()) {

        c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplGlfw_NewFrame();
        c.igNewFrame();
        
        c.glClearColor(1.0, 1.0, 1.0, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        if (draw_quadtree)
            qt.draw(myCamera);

        my_VAO.bind();
        my_shader.bind();
        my_shader.uniform(myCamera.getAssembled(), "u_assembled_matrix");
        my_shader.uniform([3]f32{ 0.7, 0, 0 }, "u_color");
        my_shader.uniform(radius, "u_radius");
        VertexArray.drawArraysInstanced(.triangle_fan, 0, circle_vertex_data.len, nodes.len);

        _ = c.igBegin("Custom Window", 0, 0);
        _ = c.igCheckbox("Show Demo Window", &show_demo_window);

        var text_size: c.ImVec2 = undefined;
        c.igCalcTextSize(&text_size, "toggle imgui demo", null, true, 1000.0);
        if (c.igButton("Print matrix", c.ImVec2{.x = text_size.x + 8, .y = text_size.y + 8})) {
            v.printMatrix(myCamera.getAssembled());
        }
        _ = c.igCheckbox("Draw quadtree", &draw_quadtree);

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
