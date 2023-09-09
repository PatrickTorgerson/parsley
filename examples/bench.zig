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
        TestEndpoint,
        TestEndpoint2,
        TestEndpoint3,
        TestEndpoint4,
        TestEndpoint5,
    }, .{ .command_descriptions = command_descriptions });
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
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
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
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {
        writer.print("Hello Satan!", .{}) catch {};
    }
};

pub const TestEndpoint3 = struct {
    pub const command_sequence = "goodbye satan";
    pub const description_line = "Say goodbye to the lord of hell";
    pub const description_full = description_line ++
        "\nSatan will probably damn you for wasting thier time";
    pub const options = &[_]parsley.Option{
        .{
            .name = "time",
            .name_short = 't',
            .description = "how long will you be gone",
            .arguments = &[_]parsley.Argument{.floating},
        },
        .{
            .name = "any-last-words",
            .name_short = null,
            .description = "you are threatining to kill them I guess",
            .arguments = &[_]parsley.Argument{},
        },
        .{
            .name = "extra",
            .name_short = 'e',
            .description = "additional context for your farewell",
            .arguments = &[_]parsley.Argument{.integer_list},
        },
    };
    pub const positionals = &[_]parsley.Positional{
        .{ "values", .integer_list },
    };
    pub fn run(
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        poss: parsley.Positionals(@This()),
        opts: parsley.Options(@This()),
    ) anyerror!void {
        writer.print("goodbye Satan\n", .{}) catch {};
        writer.print("poss: ", .{}) catch {};
        for (poss.values.items) |value| {
            writer.print("{}, ", .{value}) catch {};
        }
        writer.print("\nopts: ", .{}) catch {};
        if (opts.extra) |extra|
            for (extra.items) |value| {
                writer.print("{}, ", .{value}) catch {};
            };
    }
};

pub const TestEndpoint4 = struct {
    pub const command_sequence = "goodbye satan sub1";
    pub const description_line = "A useless subcommand";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};
    pub fn run(
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {
        writer.print("Hello Satan! sub1", .{}) catch {};
    }
};

pub const TestEndpoint5 = struct {
    pub const command_sequence = "goodbye satan sub2";
    pub const description_line = "An even more useless subcommand";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};
    pub fn run(
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {
        writer.print("Hello Satan! sub2", .{}) catch {};
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
