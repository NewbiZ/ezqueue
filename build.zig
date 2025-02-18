const std = @import("std");

const target: std.Target.Query =
    .{ .cpu_arch = .x86_64, .cpu_model = .baseline, .os_tag = .linux, .abi = .musl };

const benchmarks = [_]struct {
    name: []const u8,
    source_file: []const u8,
}{ .{
    .name = "ezqueue-bench-read",
    .source_file = "bin/bench-read.zig",
}, .{
    .name = "ezqueue-bench-ops",
    .source_file = "bin/bench-ops.zig",
} };

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    for (benchmarks) |bench| {
        const bench_exe = b.addExecutable(.{
            .name = bench.name,
            .root_source_file = b.path(bench.source_file),
            .optimize = optimize,
            .target = b.resolveTargetQuery(target),
        });
        bench_exe.root_module.addAnonymousImport(
            "libezqueue",
            .{
                .root_source_file = b.path("lib/root.zig"),
            },
        );
        bench_exe.linkLibC();
        b.installArtifact(bench_exe);
    }

    const tests = b.addTest(.{
        .root_source_file = b.path("lib/root.zig"),
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    tests.linkLibC();

    const test_cmd = b.addRunArtifact(tests);
    test_cmd.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_cmd.step);
}
