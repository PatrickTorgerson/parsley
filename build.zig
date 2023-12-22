// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2024 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const examples = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "bench", .source = "./examples/bench.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const parsley = b.addModule("parsley", .{
        .source_file = std.Build.FileSource.relative("./src/parsley.zig"),
        .dependencies = &.{},
    });

    // -- examples
    const example_step = b.step("examples", "Build all examples");
    b.default_step.dependOn(example_step);
    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = std.Build.FileSource.relative(example.source),
            .target = target,
            .optimize = optimize,
        });
        exe.addModule("parsley", parsley);
        b.installArtifact(exe);
        const run_example_cmd = b.addRunArtifact(exe);
        run_example_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_example_cmd.addArgs(args);
        }
        const run_example_step = b.step(example.name, "Run example '" ++ example.name ++ "'");
        run_example_step.dependOn(example_step);
        run_example_step.dependOn(&run_example_cmd.step);
    }

    // -- testing
    const unit_tests = b.addTest(.{
        .root_source_file = std.Build.FileSource.relative("./src/parsley.zig"),
        .target = target,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // -- formatting
    const fmt_step = b.step("fmt", "Run formatter");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "examples", "build.zig" },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);
    b.default_step.dependOn(fmt_step);
}
