const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const chameleon = b.dependency("chameleon", .{});

    const module = b.addModule("hermes", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{ .name = "chameleon", .module = chameleon.module("chameleon") },
        },
    });

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    var iter = module.dependencies.iterator();
    while (iter.next()) |e| {
        tests.addModule(e.key_ptr.*, e.value_ptr.*);
    }

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
