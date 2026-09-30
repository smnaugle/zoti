const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const ztoi_lib = b.addLibrary(
        .{
            .name = "ztoi",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zoti.zig"),
                .optimize = optimize,
                .target = target,
            }),
        },
    );
    b.installArtifact(ztoi_lib);

    const tests = b.addTest(.{
        .root_module = ztoi_lib.root_module,
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
    const run_test_step = b.addRunArtifact(tests);
    test_step.dependOn(&run_test_step.step);
}
