const std = @import("std");
const parsley = @import("parsley");

pub fn main() !void {
    var buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer buffered_writer.flush() catch {};
    var writer = buffered_writer.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    writer.writeAll("\n") catch {};
    defer writer.writeAll("\n") catch {};

    try parsley.run(allocator, &writer, &.{
        Test,
        Sub1,
        Sub2,
    }, .{
        .command_descriptions = command_descriptions,
        .help_header_fmt = "==== {s} ====\n\n",
        .help_option_description_fmt = "\n    {s}\n\n",
        .help_option_argument_fmt = "'{s}' ",
    });
}

pub const Test = struct {
    pub const command_sequence = "test";
    pub const description_line = "Command used for testing argument parsing";
    pub const description_full = description_line;

    pub const base_options = &[_]parsley.Option{
        .{
            .name = "boolean",
            .name_short = 'b',
            .description = "Accepts no value",
            .arguments = &[_]parsley.Argument{},
        },
        .{
            .name = "single",
            .name_short = 's',
            .description = "Accepts one value",
            .arguments = &[_]parsley.Argument{.integer},
        },
        .{
            .name = "optional",
            .name_short = 'o',
            .description = "Accepts zero or one value",
            .arguments = &[_]parsley.Argument{.optional_integer},
        },
        .{
            .name = "list",
            .name_short = 'l',
            .description = "Accepts any amount of values",
            .arguments = &[_]parsley.Argument{.integer_list},
        },
        .{
            .name = "tuple-no-opts",
            .name_short = null,
            .description = "Accepts 4 values",
            .arguments = &[_]parsley.Argument{ .integer, .integer, .integer, .integer },
        },
        .{
            .name = "tuple-with-opts",
            .name_short = null,
            .description = "Accepts 2 to 4 values",
            .arguments = &[_]parsley.Argument{ .integer, .integer, .optional_integer, .optional_integer },
        },
    };

    pub const options = base_options;

    pub const positionals = &[_]parsley.Positional{
        .{ "i", .integer },
        .{ "f", .floating },
        .{ "oi", .optional_integer },
    };

    pub fn run(
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        poss: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {
        try writer.print("poss: ", .{});
        try writer.print("{}, ", .{poss.i});
        try writer.print("{}, ", .{poss.f});
        try writer.print("{}, ", .{poss.oi orelse -1});
        try writer.print("\n", .{});
    }
};

const Sub1 = struct {
    pub const command_sequence = "test sub1";
    pub const description_line = "A subcommand";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};

    pub fn run(
        _: std.mem.Allocator,
        _: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {}
};

const Sub2 = struct {
    pub const command_sequence = "test sub2";
    pub const description_line = "Another subcommand";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};

    pub fn run(
        _: std.mem.Allocator,
        _: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {}
};

const command_descriptions = &[_]parsley.CommandDescription{
    .{
        .command_sequence = "",
        .line = "",
        .full = "This application serves as a space to perform ad-hoc tests of the parsley library",
    },
};
