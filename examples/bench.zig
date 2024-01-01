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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    writer.writeAll("\n") catch {};
    defer writer.writeAll("\n") catch {};

    try parsley.executeCommandLine(void, undefined, allocator, &writer, &.{
        Test,
        Sub1,
        Sub2,
    }, .{
        .command_description_resolution = .non_empty_prefer_endpoint,
        .command_descriptions = command_descriptions,
        .help_header_fmt = "==== {s} ====\n\n",
        .help_option_description_fmt = "\n    {s}\n\n",
        .help_option_argument_fmt = "'{s}' ",
        .help_topics = &.{
            .{
                .name = "license",
                .desc = "Show licensing information",
                .body =
                \\ MIT License
                \\
                \\ Copyright (c) 2023 Patrick Torgerson
                \\
                \\ Permission is hereby granted, free of charge, to any person obtaining a copy
                \\ of this software and associated documentation files (the "Software"), to deal
                \\ in the Software without restriction, including without limitation the rights
                \\ to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
                \\ copies of the Software, and to permit persons to whom the Software is
                \\ furnished to do so, subject to the following conditions:
                \\
                \\ The above copyright notice and this permission notice shall be included in all
                \\ copies or substantial portions of the Software.
                \\
                \\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                \\ IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                \\ FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                \\ AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                \\ LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                \\ OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
                \\ SOFTWARE.
                ,
            },
        },
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
        _: *void,
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
        _: *void,
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
        _: *void,
        _: std.mem.Allocator,
        _: *parsley.BufferedWriter,
        _: parsley.Positionals(@This()),
        _: parsley.Options(@This()),
    ) anyerror!void {}
};

const command_descriptions = &[_]parsley.CommandDescription{.{
    .command_sequence = "",
    .line = "",
    .full = "This application serves as a space to perform ad-hoc tests of the parsley library",
}};
