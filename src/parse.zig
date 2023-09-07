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
const EmptyComptimeStringMap = common.EmptyComptimeStringMap;
const initStructWithDefaults = common.initStructWithDefaults;

pub fn FunctionMap(comptime Writer: type, comptime endpoints: []const type) type {
    const ParseFn = *const fn (std.mem.Allocator, *Writer, ?[]const u8, *std.process.ArgIterator) anyerror!void;
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
    comptime endpoint: type,
) ParseFn {
    return struct {
        pub fn parse(allocator: std.mem.Allocator, writer: *Writer, first_arg: ?[]const u8, args: *std.process.ArgIterator) anyerror!void {
            var values: Options(endpoint.options) = undefined;

            var positionals = initStructWithDefaults(Positionals(endpoint.positionals));
            const positional_set_fns = PositionalSetFns(@TypeOf(positionals), endpoint.positionals.len);
            const use_positional_list = endpoint.positionals.len == 1 and switch (endpoint.positionals[0][1]) {
                .integer_list,
                .floating_list,
                .boolean_list,
                .string_list,
                => true,
                else => false,
            };
            if (use_positional_list) {
                @field(positionals, endpoint.positionals[0][0]) = endpoint.positionals[0][1].Type().init(allocator);
            }
            defer if (use_positional_list) {
                @field(positionals, endpoint.positionals[0][0]).deinit();
            };

            const min_positionals = minPositionals(endpoint.positionals);
            const max_positionals = maxPositionals(endpoint.positionals);
            var positional_count: usize = 0;
            var next_arg: ?[]const u8 = first_arg;
            while (next_arg) |arg| : (next_arg = args.next()) {
                if (arg.len == 0) continue;
                if (arg[0] == '-') {
                    // todo: parse option
                } else {
                    // parse positional
                    if (use_positional_list) {
                        const name = endpoint.positionals[0][0];
                        const arg_type = endpoint.positionals[0][1];
                        positional_set_fns.get(name).?(&positionals, arg) catch {
                            writer.print("expected {s} for {s} found '{s}'\n", .{ @tagName(arg_type), name, arg }) catch {};
                            return;
                        };
                    } else {
                        if (endpoint.positionals.len == 0 or positional_count >= max_positionals) {
                            writer.print("unexpected positional argument '{s}'\n", .{arg}) catch {};
                            return;
                        }
                        const name = endpoint.positionals[positional_count][0];
                        const arg_type = endpoint.positionals[positional_count][1];
                        positional_set_fns.get(name).?(&positionals, arg) catch {
                            writer.print("expected {s} for {s} found '{s}'\n", .{ @tagName(arg_type), name, arg }) catch {};
                            return;
                        };
                        positional_count += 1;
                    }
                }
            }

            if (positional_count < min_positionals) {
                writer.print("missing positional argument(s)\n", .{}) catch {};
                return;
            }

            try endpoint.run(writer, positionals, values);
        }
    }.parse;
}

const PositionalSetError =
    std.fmt.ParseIntError ||
    std.fmt.ParseFloatError ||
    error{ invalid_boolean, invalid_argument_type, OutOfMemory };

fn parseValue(comptime T: type, value: []const u8) !T {
    return switch (T) {
        i64 => try std.fmt.parseInt(i64, value, 0),
        f64 => try std.fmt.parseFloat(f64, value),
        bool => if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else error.invalid_boolean,
        []const u8 => return value,
        ?i64,
        ?f64,
        ?bool,
        ?[]const u8,
        => error.invalid_argument_type,
        else => error.invalid_argument_type,
    };
}

fn PositionalSetFns(comptime positionals: type, comptime size: usize) type {
    const SetFn = *const fn (*positionals, []const u8) PositionalSetError!void;
    if (size == 0) return EmptyComptimeStringMap(SetFn);
    const ParseFnKV = struct { []const u8, SetFn };
    var set_fn_arr: [size]ParseFnKV = undefined;
    inline for (std.meta.fields(positionals), 0..) |field, i| {
        set_fn_arr[i][0] = field.name;
        set_fn_arr[i][1] = generatePositionalSetFunction(SetFn, positionals, field.name, field.type);
    }
    return std.ComptimeStringMap(SetFn, set_fn_arr);
}

fn generatePositionalSetFunction(
    comptime SetFn: type,
    comptime positionals: type,
    comptime field_name: []const u8,
    comptime field_type: type,
) SetFn {
    return struct {
        pub fn set(p: *positionals, value: []const u8) PositionalSetError!void {
            const T = comptime if (std.meta.trait.is(.Optional)(field_type))
                std.meta.Child(field_type)
            else
                field_type;
            const is_struct = comptime std.meta.trait.is(.Struct)(T);
            if (is_struct)
                try @field(p, field_name).append(try parseValue(std.meta.Child(T.Slice), value))
            else
                @field(p, field_name) = try parseValue(T, value);
        }
    }.set;
}

fn maxPositionals(comptime positionals: []const Positional) usize {
    if (positionals.len == 0) return 0;
    switch (positionals[0][1]) {
        // list args must be the only member
        .integer_list,
        .floating_list,
        .boolean_list,
        .string_list,
        => return std.math.maxInt(usize),
        .optional_integer,
        .optional_floating,
        .optional_boolean,
        .optional_string,
        .integer,
        .floating,
        .boolean,
        .string,
        => return positionals.len,
    }
}

fn minPositionals(comptime positionals: []const Positional) usize {
    if (positionals.len == 0) return 0;
    var optionals: usize = 0;
    while (optionals < positionals.len) {
        switch (positionals[positionals.len - 1 - optionals][1]) {
            .integer_list,
            .floating_list,
            .boolean_list,
            .string_list,
            => return 0,
            .optional_integer,
            .optional_floating,
            .optional_boolean,
            .optional_string,
            => optionals += 1,
            .integer,
            .floating,
            .boolean,
            .string,
            => break,
        }
    }
    return positionals.len - optionals;
}
