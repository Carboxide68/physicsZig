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
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "physicsZig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const imgui = "deps/cimgui/imgui/";
    exe.addCSourceFiles(&[_][]const u8{
        imgui ++ "imgui.cpp",
        imgui ++ "imgui_draw.cpp",
        imgui ++ "imgui_tables.cpp",
        imgui ++ "imgui_widgets.cpp",
        imgui ++ "imgui_demo.cpp",
        imgui ++ "backends/imgui_impl_opengl3.cpp",
        imgui ++ "backends/imgui_impl_glfw.cpp",
        "deps/cimgui/cimgui.cpp",
    }, &[_][]const u8{"-DIMGUI_IMPL_API=extern \"C\""});

    var enable_tracy = b.option(bool, "tracy_enable", "Enable tracy for profiling") orelse false;
    //enable_tracy = enable_tracy and optimize != .Debug;
    const opts = b.addOptions();
    exe.addOptions("build_options", opts);
    opts.addOption(bool, "enable_tracy", enable_tracy);
    if (enable_tracy) {
        exe.addCSourceFile(
            "deps/tracy/public/TracyClient.cpp",
            &.{ "-g", "-DTRACY_ENABLE=1" },
        );
        exe.addIncludePath("deps/tracy/public/");
    }

    exe.addLibraryPath("deps/lib/");
    exe.addIncludePath("deps/include/");
    exe.addIncludePath("deps/cimgui/");
    exe.addIncludePath(imgui);
    exe.addModule("glfw", glfw.module(b));

    if (target.isWindows()) {
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("shell32");
        exe.linkSystemLibrary("glew32s");
    } else {
        exe.linkSystemLibrary("glu");
        exe.linkSystemLibrary("GL");
        exe.linkSystemLibrary("glew");
    }

    glfw.link(b, exe, .{ .wayland = false }) catch unreachable;
    exe.linkLibC();
    exe.linkLibCpp();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
