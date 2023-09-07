// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const common = @import("common.zig");
const Option = common.Option;
const Positional = common.Positional;
const Argument = common.Argument;
const Positionals = common.Positionals;
const Options = common.Options;

pub fn FunctionMap(comptime Writer: type, comptime endpoints: []const type) type {
    const ParseFn = *const fn (*Writer, ?[]const u8, *std.process.ArgIterator) anyerror!void;
    const ParseFnKV = struct { []const u8, ParseFn };
    var parse_fn_arr: [endpoints.len]ParseFnKV = undefined;
    inline for (endpoints, 0..) |endpoint, i| {
        parse_fn_arr[i][0] = endpoint.command_sequence;
        parse_fn_arr[i][1] = generateParseFunction(Writer, ParseFn, endpoint);
    }
    return std.ComptimeStringMap(ParseFn, parse_fn_arr);
}

fn generateParseFunction(
    comptime Writer: type,
    comptime ParseFn: type,
    comptime cmd: type,
) ParseFn {
    return struct {
        pub fn parse(writer: *Writer, first_arg: ?[]const u8, args: *std.process.ArgIterator) anyerror!void {
            _ = first_arg;
            _ = args;
            // TODO: parse from commandline
            var values: Options(cmd.options) = undefined;
            var positionals: Positionals(cmd.positionals) = undefined;
            try cmd.run(writer, positionals, values);
        }
    }.parse;
}
