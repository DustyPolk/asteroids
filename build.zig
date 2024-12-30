const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "asteroids",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add raylib paths
    exe.addLibraryPath(.{ .cwd_relative = "C:/raylib/lib" });
    exe.addIncludePath(.{ .cwd_relative = "C:/raylib/include" });

    // Link with raylib and Windows libraries
    exe.addObjectFile(.{ .cwd_relative = "C:/raylib/lib/libraylib.a" });
    exe.linkSystemLibrary("opengl32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("winmm");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);
}
