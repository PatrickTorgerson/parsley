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
const isSingleOptionalStruct = common.isSingleOptionalStruct;

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
            var options = initStructWithDefaults(Options(endpoint));
            defer deinitOptions(@TypeOf(options), &options);
            const option_set_fns = OptionSetFns(@TypeOf(options));
            const option_ids = OptionValueIdentifiers(@TypeOf(options));
            const list_init_fns = ArrayListInitFns(@TypeOf(options));

            var positionals = initStructWithDefaults(Positionals(endpoint));
            const min_positionals = minPositionals(endpoint.positionals);
            const max_positionals = maxPositionals(endpoint.positionals);
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
                    const opt = parseOptionName(arg);
                    if (lookupOption(endpoint.options, opt)) |option| {
                        if (option.arguments.len == 0) {
                            // bool init
                            option_set_fns.get(option_ids.get(option.name, 0)).?(&options, "") catch |err| {
                                writer.print("({s}): ", .{@errorName(err)}) catch {};
                                writer.print("--{s}\n", .{option.name}) catch {};
                                return;
                            };
                            next_arg = args.next();
                            continue :arg_loop;
                        } else if (option.arguments.len == 1 and option.arguments[0].isList()) {
                            // list init, deinits occor via deinitOptions()
                            list_init_fns.get(option.name).?(&options, allocator);
                        } else if (option.arguments.len >= 2) {
                            // tuple init
                            option_set_fns.get(option_ids.get(option.name, option.arguments.len)).?(&options, "") catch |err| {
                                writer.print("({s}): ", .{@errorName(err)}) catch {};
                                writer.print("on tuple init --{s}\n", .{option.name}) catch {};
                                return;
                            };
                        }
                        const min_argumnts = minArguments(option.arguments);
                        var i: usize = 0;
                        while (i < option.arguments.len) {
                            const expected_arg = option.arguments[i];
                            const next_value = args.next();
                            if (next_value) |value| {
                                if (value[0] == '-') {
                                    if (option.arguments.len == 1 and option.arguments[0].isOptional()) {
                                        option_set_fns.get(option_ids.get(option.name, 0)).?(&options, "") catch |err| {
                                            writer.print("({s}): ", .{@errorName(err)}) catch {};
                                            writer.print("--{s}\n", .{option.name}) catch {};
                                            return;
                                        };
                                    } else if (i < min_argumnts) {
                                        writer.print("option --{s} is mising arguments\n", .{option.name}) catch {};
                                        return;
                                    }
                                    next_arg = next_value;
                                    continue :arg_loop;
                                }
                                option_set_fns.get(option_ids.get(option.name, i)).?(&options, value) catch |err| {
                                    writer.print("({s}): ", .{@errorName(err)}) catch {};
                                    writer.print(
                                        "expected {s} for --{s} found '{s}'\n",
                                        .{ @tagName(expected_arg), option.name, value },
                                    ) catch {};
                                    return;
                                };
                                if (!option.arguments[0].isList()) i += 1;
                            } else {
                                if (option.arguments.len == 1 and option.arguments[0].isOptional()) {
                                    option_set_fns.get(option_ids.get(option.name, 0)).?(&options, "") catch |err| {
                                        writer.print("({s}): ", .{@errorName(err)}) catch {};
                                        writer.print("--{s}\n", .{option.name}) catch {};
                                        return;
                                    };
                                } else if (i < min_argumnts) {
                                    writer.print("option --{s} is mising arguments\n", .{option.name}) catch {};
                                    return;
                                }
                                next_arg = next_value;
                                continue :arg_loop;
                            }
                        }
                    } else {
                        writer.print("unrecognized option '{s}'\n", .{opt}) catch {};
                        return;
                    }
                    next_arg = args.next();
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
                    next_arg = args.next();
                }
            }

            if (positional_count < min_positionals) {
                writer.print("missing positional argument(s)\n", .{}) catch {};
                return;
            }

            try endpoint.run(allocator, writer, positionals, options);
        }
    }.parse;
}

fn parseOptionName(arg: []const u8) []const u8 {
    var end: usize = 0;
    while (end < arg.len and arg[end] != '=' and arg[end] != ':' and arg[end] != ' ')
        end += 1;
    return arg[0..end];
}

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

fn parseValue(comptime T: type, value: []const u8) !T {
    return switch (T) {
        i64 => try std.fmt.parseInt(i64, value, 0),
        f64 => try std.fmt.parseFloat(f64, value),
        bool => if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else error.invalid_boolean,
        []const u8 => return value,
        else => error.invalid_argument_type,
    };
}

const SetFnError =
    std.fmt.ParseIntError ||
    std.fmt.ParseFloatError ||
    error{ invalid_boolean, invalid_argument_type, OutOfMemory };

fn PositionalSetFns(comptime positionals: type, comptime size: usize) type {
    const SetFn = *const fn (*positionals, []const u8) SetFnError!void;
    if (size == 0) return EmptyComptimeStringMap(SetFn);
    const SetFnKV = struct { []const u8, SetFn };
    var set_fn_arr: [size]SetFnKV = undefined;
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
        pub fn set(p: *positionals, value: []const u8) SetFnError!void {
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

fn ArrayListInitFns(comptime options: type) type {
    const InitFn = *const fn (*options, std.mem.Allocator) void;
    const size = std.meta.fields(options).len;
    if (size == 0) return EmptyComptimeStringMap(InitFn);
    const InitFnKV = struct { []const u8, InitFn };
    var init_fn_arr: [size]InitFnKV = undefined;
    var i: usize = 0;
    inline for (std.meta.fields(options)) |field| {
        if (isOptionalArrayList(field.type)) {
            init_fn_arr[i][0] = field.name;
            init_fn_arr[i][1] = struct {
                pub fn init(opts: *options, ally: std.mem.Allocator) void {
                    if (@field(opts, field.name) == null)
                        @field(opts, field.name) = std.meta.Child(field.type).init(ally);
                }
            }.init;
            i += 1;
        }
    }
    if (i == 0) return EmptyComptimeStringMap(InitFn);
    return std.ComptimeStringMap(InitFn, init_fn_arr[0..i]);
}

fn deinitOptions(comptime OptionsType: type, options: *OptionsType) void {
    inline for (std.meta.fields(OptionsType)) |field| {
        if (comptime isOptionalArrayList(field.type)) {
            if (@field(options, field.name)) |*list| {
                list.deinit();
            }
        }
    }
}

fn isOptionalArrayList(comptime T: type) bool {
    return std.meta.trait.is(.Optional)(T) and
        std.meta.trait.is(.Struct)(std.meta.Child(T)) and
        std.meta.trait.hasFields(std.meta.Child(T), .{ "items", "capacity", "allocator" }) and
        std.meta.trait.hasDecls(std.meta.Child(T), .{ "init", "deinit", "append" });
}

fn OptionSetFns(comptime options: type) type {
    const SetFn = *const fn (*options, []const u8) SetFnError!void;
    const size = optionValueCount(options);
    if (size == 0) return EmptyComptimeStringMap(SetFn);
    const SetFnKV = struct { []const u8, SetFn };
    var set_fn_arr: [size]SetFnKV = undefined;
    var i: usize = 0;
    inline for (std.meta.fields(options)) |field| {
        if (std.meta.trait.is(.Optional)(field.type) and std.meta.trait.isTuple(std.meta.Child(field.type))) {
            inline for (std.meta.fields(std.meta.Child(field.type)), 0..) |tuple_field, tuple_index| {
                set_fn_arr[i][0] = field.name ++ tuple_field.name;
                set_fn_arr[i][1] = generateOptionSetFunction(
                    SetFn,
                    options,
                    field.name,
                    tuple_index,
                    false,
                    tuple_field.type,
                );
                i += 1;
            }
            set_fn_arr[i][0] = field.name ++ "_tupleinit";
            set_fn_arr[i][1] = struct {
                pub fn set(p: *options, _: []const u8) SetFnError!void {
                    @field(p, field.name) = initStructWithDefaults(std.meta.Child(field.type));
                }
            }.set;
            i += 1;
        } else {
            set_fn_arr[i][0] = field.name ++ "0";
            set_fn_arr[i][1] = generateOptionSetFunction(
                SetFn,
                options,
                field.name,
                0,
                true,
                field.type,
            );
            i += 1;
        }
    }
    return std.ComptimeStringMap(SetFn, set_fn_arr);
}

fn generateOptionSetFunction(
    comptime SetFn: type,
    comptime options: type,
    comptime field_name: []const u8,
    comptime index: usize,
    comptime single: bool,
    comptime field_type: type,
) SetFn {
    return struct {
        pub fn set(p: *options, value: []const u8) SetFnError!void {
            if (comptime std.meta.trait.is(.Bool)(field_type))
                @field(p, field_name) = true
            else if (comptime isSingleOptionalStruct(field_type)) {
                const ValueType = std.meta.fieldInfo(field_type, std.enums.nameCast(std.meta.FieldEnum(field_type), "value")).type;
                @field(p, field_name) = .{
                    .present = true,
                    .value = if (value.len == 0) null else try parseValue(std.meta.Child(ValueType), value),
                };
            } else {
                const T = comptime if (std.meta.trait.is(.Optional)(field_type))
                    std.meta.Child(field_type)
                else
                    field_type;

                const is_struct = comptime std.meta.trait.is(.Struct)(T);
                if (comptime single) {
                    if (is_struct) // arrayList
                        try @field(p, field_name).?.append(try parseValue(std.meta.Child(T.Slice), value))
                    else
                        @field(p, field_name) = try parseValue(T, value);
                } else {
                    @field(p, field_name).?[index] = try parseValue(T, value);
                }
            }
        }
    }.set;
}

fn optionValueCount(comptime options: type) usize {
    return comptime blk: {
        var size: usize = 0;
        inline for (std.meta.fields(options)) |field| {
            if (std.meta.trait.is(.Optional)(field.type) and std.meta.trait.isTuple(std.meta.Child(field.type)))
                size += std.meta.fields(std.meta.Child(field.type)).len + 1
            else
                size += 1;
        }
        break :blk size;
    };
}

fn OptionValueIdentifiers(comptime options: type) type {
    const precomputed = comptime blk: {
        const size = optionValueCount(options);
        var idbuffer: [size][]const u8 = undefined;
        const KV = struct { []const u8, usize };
        var mappings: [std.meta.fields(options).len]KV = undefined;
        var i: usize = 0;
        inline for (std.meta.fields(options), 0..) |field, fi| {
            mappings[fi] = .{ field.name, i };
            if (std.meta.trait.is(.Optional)(field.type) and std.meta.trait.isTuple(std.meta.Child(field.type))) {
                inline for (std.meta.fields(std.meta.Child(field.type))) |tuple_field| {
                    idbuffer[i] = field.name ++ tuple_field.name;
                    i += 1;
                }
                idbuffer[i] = field.name ++ "_tupleinit";
                i += 1;
            } else {
                idbuffer[i] = field.name ++ "0";
                i += 1;
            }
        }
        break :blk .{
            .idbuffer = idbuffer,
            .mappings = if (mappings.len > 0)
                std.ComptimeStringMap(usize, mappings)
            else
                EmptyComptimeStringMap(usize),
        };
    };
    return struct {
        pub const idbuffer = precomputed.idbuffer;
        pub fn get(field: []const u8, index: usize) []const u8 {
            if (idbuffer.len == 0) return "";
            const start = precomputed.mappings.get(field).?;
            return idbuffer[start + index];
        }
    };
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
