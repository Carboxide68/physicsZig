const std = @import("std");
const glfw = @import("deps/mach-glfw/build.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("physicsZig", "src/main.zig");

    const imgui = "deps/cimgui/imgui/";
    exe.addCSourceFiles(&[_][]const u8 {
        imgui++"imgui.cpp",
        imgui++"imgui_draw.cpp",
        imgui++"imgui_tables.cpp",
        imgui++"imgui_widgets.cpp",
        imgui++"imgui_demo.cpp",
        imgui++"backends/imgui_impl_opengl3.cpp",
        imgui++"backends/imgui_impl_glfw.cpp",
        "deps/cimgui/cimgui.cpp",
    }, &[_][]const u8 {"-DIMGUI_IMPL_API=extern \"C\""});
    const libs = [_][:0]const u8{
        "glu",
        "GL",
        "glew",
    };

    exe.addLibPath("deps/lib/");
    exe.addIncludeDir("deps/include/");
    exe.addIncludeDir("deps/cimgui/");
    exe.addIncludeDir(imgui);
    exe.addPackagePath("glfw", "deps/mach-glfw/src/main.zig");
    glfw.link(b, exe, .{});

    exe.linkLibC();
    exe.linkLibCpp();
    for (libs) |lib| {
        exe.linkSystemLibrary(lib);
    }

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
