// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2024 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const parsley = @import("parsley");

pub fn main() !void {
    var buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer buffered_writer.flush() catch {};
    var writer = buffered_writer.writer();

    const stdin = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var input_buffer = std.ArrayListUnmanaged(u8){};
    defer input_buffer.deinit(allocator);
    const input_buffer_writer = input_buffer.writer(allocator);

    writer.writeAll("\n") catch {};
    defer writer.writeAll("\n") catch {};

    while (true) {
        writer.print("> ", .{}) catch {};
        buffered_writer.flush() catch {};
        input_buffer.items.len = 0;
        try stdin.streamUntilDelimiter(input_buffer_writer, '\n', null);
        const input = std.mem.trim(u8, input_buffer.items, " \n\t\r");
        if (std.mem.eql(u8, input, "exit")) break;
        try parsley.executeString(input, allocator, &writer, &.{
            Root,
            Exit,
            Echo,
            Sum,
        }, .{});
    }
}

const Echo = struct {
    pub const command_sequence = "echo";
    pub const description_line = "Prints all positional args";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{
        .{ "args", .string_list },
    };

    pub fn run(
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        poss: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {
        for (poss.args.items) |arg| {
            writer.print("{s} ", .{arg}) catch {};
        }
        writer.writeByte('\n') catch {};
    }
};

const Sum = struct {
    pub const command_sequence = "sum";
    pub const description_line = "Add two numbers, print the sum";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{
        .{ "left_operand", .floating },
        .{ "right_operand", .floating },
    };

    pub fn run(
        _: std.mem.Allocator,
        writer: *parsley.BufferedWriter,
        poss: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {
        const sum = poss.left_operand + poss.right_operand;
        writer.print("{d} + {d} = {d}\n", .{ poss.left_operand, poss.right_operand, sum }) catch {};
    }
};

/// just so no op doesn't print help
const Root = struct {
    pub const command_sequence = "";
    pub const description_line = "";
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

/// just so exit appears in help msgs
const Exit = struct {
    pub const command_sequence = "exit";
    pub const description_line = "Exit the repl application";
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
