const std = @import("std");
const parsley = @import("parsley");

pub fn main() !void {
    try parsley.parse(&.{TestEndpoint}, .{});
}

const TestEndpoint = struct {
    pub const command_sequence = "hello world";
    pub const description_line = "A test endpoint";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Argument{};
    pub fn run(_: parsley.Positionals(positionals), _: parsley.Options(options)) void {}
};
