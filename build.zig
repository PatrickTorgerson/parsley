const std = @import("std");

const examples = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "bench", .source = "examples/bench.zig" },
};

pub fn module(b: *std.Build) *std.Build.Module {
    return b.addModule("parsley", .{
        .source_file = .{ .path = sdkPath("/src/parsley.zig") },
        .dependencies = &.{},
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const parsley = module(b);

    // -- examples

    const example_step = b.step("examples", "Build all examples");

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = .{ .path = example.source },
            .target = target,
            .optimize = optimize,
        });
        exe.addModule("parsley", parsley);

        const instal_step = &b.addInstallArtifact(exe).step;
        example_step.dependOn(instal_step);

        const run_example_cmd = b.addRunArtifact(exe);
        run_example_cmd.step.dependOn(instal_step);
        if (b.args) |args| {
            run_example_cmd.addArgs(args);
        }

        const run_example_step = b.step(example.name, "Run example '" ++ example.name ++ "'");
        run_example_step.dependOn(example_step);
        run_example_step.dependOn(&run_example_cmd.step);
    }

    // -- testing

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = sdkPath("/src/parsley.zig") },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}
