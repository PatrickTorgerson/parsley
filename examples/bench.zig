const std = @import("std");
const parsley = @import("parsley");

const Writer = @TypeOf(std.io.getStdOut().writer());

pub fn main() !void {
    var writer: Writer = std.io.getStdOut().writer();
    try parsley.parse(
        &writer,
        &.{
            TestEndpoint,
            TestEndpoint2,
            TestEndpoint3,
        },
        .{ .command_descriptions = command_descriptions },
    );
}

pub const TestEndpoint = struct {
    pub const command_sequence = "hello world";
    pub const description_line = "A test endpoint";
    pub const description_full = "A large amount of information";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Argument{};
    pub fn run(
        _: *Writer,
        _: parsley.Positionals(positionals),
        _: parsley.Options(options),
    ) void {}
};

pub const TestEndpoint2 = struct {
    pub const command_sequence = "hello satan";
    pub const description_line = "satan is bad";
    pub const description_full = "satan is bad full";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Argument{};
    pub fn run(
        _: *Writer,
        _: parsley.Positionals(positionals),
        _: parsley.Options(options),
    ) void {}
};

pub const TestEndpoint3 = struct {
    pub const command_sequence = "goodbye satan";
    pub const description_line = "satan is good";
    pub const description_full = "satan is good full";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Argument{};
    pub fn run(
        _: *Writer,
        _: parsley.Positionals(positionals),
        _: parsley.Options(options),
    ) void {}
};

const command_descriptions = &[_]parsley.CommandDescription{
    .{
        .command_sequence = "",
        .line = "the almighty root command",
        .full = "the almighty root command -- full",
    },
    .{
        .command_sequence = "hello",
        .line = "some base command",
        .full = "even more information",
    },
    .{
        .command_sequence = "goodbye",
        .line = "goodbye some base command",
        .full = "goodbye even more information",
    },
};
