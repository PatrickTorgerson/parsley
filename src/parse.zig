// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const SetFnMap = @import("setfnmap.zig").SetFnMap;
const help = @import("help.zig");
const common = @import("common.zig");
const Context = common.Context;
const Configuration = common.Configuration;
const Option = common.Option;
const Positional = common.Positional;
const Argument = common.Argument;
const Positionals = common.Positionals;
const Options = common.Options;
const EmptyComptimeStringMap = common.EmptyComptimeStringMap;

/// generate a std.ComptimeStringMap() mapping command sequences to parse functions
pub fn FunctionMap(comptime ctx: Context) type {
    const ParseFn = *const fn (
        std.mem.Allocator,
        *ctx.WriterType,
        ?[]const u8,
        *std.process.ArgIterator,
        []const u8,
    ) anyerror!void;
    const ParseFnKV = struct { []const u8, ParseFn };
    var parse_fn_arr: [ctx.endpoints.len]ParseFnKV = undefined;
    inline for (ctx.endpoints, 0..) |endpoint, i| {
        parse_fn_arr[i][0] = endpoint.command_sequence;
        parse_fn_arr[i][1] = generateParseFunction(ctx, ParseFn, endpoint);
    }
    return std.ComptimeStringMap(ParseFn, parse_fn_arr);
}

/// generate a parse function for the given endpoint
fn generateParseFunction(
    comptime ctx: Context,
    comptime ParseFn: type,
    comptime endpoint: type,
) ParseFn {
    return struct {
        pub fn parse(
            allocator: std.mem.Allocator,
            writer: *ctx.WriterType,
            first_arg: ?[]const u8,
            args: *std.process.ArgIterator,
            exename: []const u8,
        ) anyerror!void {
            var options = std.mem.zeroInit(Options(endpoint), .{});
            defer deinitOptions(@TypeOf(options), &options, allocator);
            const option_set_fns = SetFnMap(@TypeOf(options));
            const init_fns = InitFns(@TypeOf(options));

            var positionals = std.mem.zeroInit(Positionals(endpoint), .{});
            const min_positionals = minPositionals(endpoint.positionals);
            const max_positionals = maxPositionals(endpoint.positionals);
            const positional_set_fns = SetFnMap(@TypeOf(positionals));

            const use_positional_list = endpoint.positionals.len == 1 and endpoint.positionals[0][1].isList();
            defer if (use_positional_list) {
                @field(positionals, endpoint.positionals[0][0]).deinit(allocator);
            };

            var no_options = false;
            var positional_count: usize = 0;
            var next_arg: ?[]const u8 = first_arg;

            arg_loop: while (next_arg) |arg| {
                if (arg[0] == '-' and arg.len == 1) {
                    next_arg = args.next();
                    continue :arg_loop;
                }
                if (std.mem.eql(u8, arg, "--")) {
                    next_arg = args.next();
                    no_options = true;
                    continue :arg_loop;
                }
                if (!no_options and arg[0] == '-' and !std.ascii.isDigit(arg[1])) {
                    // parse option
                    const opt = arg;
                    if (lookupOption(endpoint.options, opt)) |option| {
                        if (option.arguments.len == 0) {
                            // bool init
                            option_set_fns.get(option.name, 0).?(allocator, &options, "true") catch |err| {
                                writer.print("({s}): error on bool init --{s}\n", .{ @errorName(err), option.name }) catch {};
                                return;
                            };
                            next_arg = args.next();
                            continue :arg_loop;
                        } else if (option.arguments.len == 1 and option.arguments[0].isList()) {
                            // list init, deinits occor via deinitOptions()
                            init_fns.get(option.name).?(&options);
                        } else if (option.arguments.len >= 2) {
                            // tuple init
                            init_fns.get(option.name).?(&options);
                        }
                        const min_argumnts = minArguments(option.arguments);
                        var i: usize = 0;
                        while (i < option.arguments.len) {
                            const expected_arg = option.arguments[i];
                            const next_value = args.next();
                            if (next_value) |value| {
                                if (value[0] == '-') {
                                    if (option.arguments.len == 1 and option.arguments[0].isOptional()) {
                                        option_set_fns.get(option.name, 0).?(allocator, &options, "") catch |err| {
                                            writer.print("({s}): on single optional set --{s}\n", .{ @errorName(err), option.name }) catch {};
                                            return;
                                        };
                                    } else if (i < min_argumnts) {
                                        writer.print("option {s} is missing {} argument(s)\n", .{ opt, min_argumnts - i }) catch {};
                                        help.writeOptionSigniture(ctx, writer, option) catch {};
                                        writer.print("\nsee '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                                        return;
                                    }
                                    next_arg = next_value;
                                    continue :arg_loop;
                                }
                                option_set_fns.get(option.name, i).?(allocator, &options, value) catch {
                                    writer.print("expected {s} for {s} found '{s}'\n", .{
                                        @tagName(expected_arg.scalar()),
                                        opt,
                                        value,
                                    }) catch {};
                                    help.writeOptionSigniture(ctx, writer, option) catch {};
                                    writer.print("\nsee '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                                    return;
                                };
                                if (!option.arguments[0].isList()) i += 1;
                            } else {
                                // no more args
                                if (option.arguments.len == 1 and option.arguments[0].isOptional()) {
                                    option_set_fns.get(option.name, 0).?(allocator, &options, "") catch |err| {
                                        writer.print("({s}): on single optional set --{s}\n", .{ @errorName(err), option.name }) catch {};
                                        return;
                                    };
                                } else if (i < min_argumnts) {
                                    writer.print("option {s} is missing {} argument(s)\n", .{ opt, min_argumnts - i }) catch {};
                                    help.writeOptionSigniture(ctx, writer, option) catch {};
                                    writer.print("\nsee '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                                    return;
                                }
                                next_arg = next_value;
                                continue :arg_loop;
                            }
                        }
                    } else {
                        writer.print("unrecognized option '{s}'\n", .{opt}) catch {};
                        writer.print("see '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                        return;
                    }
                    next_arg = args.next();
                } else {
                    // parse positional
                    if (endpoint.positionals.len == 0 or positional_count >= max_positionals) {
                        writer.print("unexpected positional argument '{s}'\n", .{arg}) catch {};
                        help.writeUsage(ctx, endpoint, exename, writer) catch {};
                        writer.print("\nsee '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                        return;
                    }
                    const name = endpoint.positionals[positional_count][0];
                    const arg_type = endpoint.positionals[positional_count][1];
                    positional_set_fns.get(name, 0).?(allocator, &positionals, arg) catch {
                        writer.print("expected {s} for positional {s}, found '{s}'\n", .{ @tagName(arg_type.scalar()), name, arg }) catch {};
                        help.writeUsage(ctx, endpoint, exename, writer) catch {};
                        writer.print("\nsee '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                        return;
                    };
                    if (!use_positional_list)
                        positional_count += 1;
                    next_arg = args.next();
                }
            }

            if (positional_count < min_positionals) {
                writer.print("missing {} positional argument(s)\n", .{min_positionals - positional_count}) catch {};
                help.writeUsage(ctx, endpoint, exename, writer) catch {};
                writer.print("\nsee '{s} {s} --help'\n", .{ exename, endpoint.command_sequence }) catch {};
                return;
            }

            try endpoint.run(allocator, writer, positionals, options);
        }
    }.parse;
}

/// search `options` for an option with name or name_short equal to `opt` minus dash prefix
fn lookupOption(comptime options: []const Option, opt: []const u8) ?Option {
    const start = blk: {
        var i: usize = 0;
        if (i < opt.len and opt[i] == '-') i += 1;
        if (i < opt.len and opt[i] == '-') i += 1;
        break :blk i;
    };
    for (options) |option| {
        if (opt[start..].len == 1 and opt[start] == option.name_short)
            return option;
        if (std.mem.eql(u8, opt[start..], option.name))
            return option;
    }
    return null;
}

/// generate a std.ComptimeStringMap() to map field names to init fns
fn InitFns(comptime T: type) type {
    const InitFn = *const fn (*T) void;
    const size = std.meta.fields(T).len;
    if (size == 0) return EmptyComptimeStringMap(InitFn);
    const InitFnKV = struct { []const u8, InitFn };
    var init_fn_arr: [size]InitFnKV = undefined;
    var i: usize = 0;
    inline for (std.meta.fields(T)) |field| {
        if (comptime isOptionalArrayList(field.type)) {
            init_fn_arr[i][0] = field.name;
            init_fn_arr[i][1] = struct {
                pub fn init(opts: *T) void {
                    if (@field(opts, field.name) == null)
                        @field(opts, field.name) = std.meta.Child(field.type){};
                }
            }.init;
            i += 1;
        } else if (comptime std.meta.trait.is(.Optional)(field.type) and std.meta.trait.isTuple(std.meta.Child(field.type))) {
            init_fn_arr[i][0] = field.name;
            init_fn_arr[i][1] = struct {
                pub fn init(opts: *T) void {
                    if (@field(opts, field.name) == null)
                        @field(opts, field.name) = std.mem.zeroes(std.meta.Child(field.type));
                }
            }.init;
            i += 1;
        }
    }
    if (i == 0) return EmptyComptimeStringMap(InitFn);
    return std.ComptimeStringMap(InitFn, init_fn_arr[0..i]);
}

/// call deinit() on all fields that define deinit()
fn deinitOptions(comptime OptionsType: type, options: *OptionsType, ally: std.mem.Allocator) void {
    inline for (std.meta.fields(OptionsType)) |field| {
        if (comptime isOptionalArrayList(field.type)) {
            if (@field(options, field.name)) |*list| {
                list.deinit(ally);
            }
        }
    }
}

/// determine if `T` is an optional array list
fn isOptionalArrayList(comptime T: type) bool {
    return std.meta.trait.is(.Optional)(T) and
        std.meta.trait.is(.Struct)(std.meta.Child(T)) and
        std.meta.trait.hasFields(std.meta.Child(T), .{ "items", "capacity" }) and
        std.meta.trait.hasFunctions(std.meta.Child(T), .{ "initCapacity", "deinit", "append" });
}

/// determine the maximum number of positionals that could be specified
/// with the given positions argument types
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

/// determine the minimum number of positionals that could be specified
/// with the given positions argument types
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

/// determine the maximum number of option arguments that could be specified
/// with the given argument types
fn minArguments(arguments: []const Argument) usize {
    if (arguments.len == 0) return 0;
    var optionals: usize = 0;
    while (optionals < arguments.len) {
        switch (arguments[arguments.len - 1 - optionals]) {
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
    return arguments.len - optionals;
}
