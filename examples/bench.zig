const std = @import("std");
const parsley = @import("parsley");

const Writer = @TypeOf(std.io.getStdOut().writer());

pub fn main() !void {
    var writer: Writer = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    writer.writeAll("\n") catch {};
    defer writer.writeAll("\n") catch {};

    try parsley.run(
        allocator,
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
    pub const description_line = "Say hello to the home of the sapians";
    pub const description_full = description_line ++
        "\nI'm sure the world will be appretiative";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{
        .{ "name", .string },
    };
    pub fn run(
        writer: *Writer,
        _: parsley.Positionals(positionals),
        _: parsley.Options(options),
    ) anyerror!void {
        writer.print("Hello world!", .{}) catch {};
    }
};

pub const TestEndpoint2 = struct {
    pub const command_sequence = "hello satan";
    pub const description_line = "Say hello to the lord of hell";
    pub const description_full = description_line ++
        "\nSatan will probably damn you for wasting thier time";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};
    pub fn run(
        writer: *Writer,
        _: parsley.Positionals(positionals),
        _: parsley.Options(options),
    ) anyerror!void {
        writer.print("Hello Satan!", .{}) catch {};
    }
};

pub const TestEndpoint3 = struct {
    pub const command_sequence = "goodbye satan";
    pub const description_line = "Say goodbye to the lord of hell";
    pub const description_full = description_line ++
        "\nSatan will probably damn you for wasting thier time";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};
    pub fn run(
        writer: *Writer,
        _: parsley.Positionals(positionals),
        _: parsley.Options(options),
    ) anyerror!void {
        writer.print("Goodbye Satan!", .{}) catch {};
    }
};

const command_descriptions = &[_]parsley.CommandDescription{
    .{
        .command_sequence = "",
        .line = "",
        .full = "This application serves as a space to perform ad-hoc tests of the parsley library",
    },
    .{
        .command_sequence = "hello",
        .line = "Say hello to a friend",
        .full = "Say hello to a friend\nWe have subcommands but are not callable",
    },
    .{
        .command_sequence = "goodbye",
        .line = "Say goodbye to a friend",
        .full = "Say goodbye to a friend\nWe have subcommands but are not callable",
    },
};
