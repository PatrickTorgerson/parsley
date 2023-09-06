// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const ComptimeStringMapBuilder = @import("comptimestringmapbuilder.zig").ComptimeStringMapBuilder;
// pub const Writer = @import("writer.zig");

pub const Option = struct {
    // required name of the option
    /// must follow the regex `[a-zA-Z_-]+`
    /// do not include the dash prefix
    name: []const u8,
    /// optional short alias
    name_short: ?u8 = null,
    /// a description of the option, will appear
    /// in the command's help text
    description: []const u8,
    /// a list of expected argument types
    arguments: []const Argument,
};

/// enum of possible argument types
pub const Argument = enum {
    integer,
    floating,
    boolean,
    string,
    optional_integer,
    optional_floating,
    optional_boolean,
    optional_string,
    integer_list,
    floating_list,
    boolean_list,
    string_list,

    pub fn Type(comptime this: Argument) type {
        return switch (this) {
            .integer => i64,
            .floating => f64,
            .boolean => bool,
            .string => []const u8,
            .optional_integer => ?i64,
            .optional_floating => ?f64,
            .optional_boolean => ?bool,
            .optional_string => ?[]const u8,
            .integer_list => std.ArrayList(i64),
            .floating_list => std.ArrayList(f64),
            .boolean_list => std.ArrayList(bool),
            .string_list => std.ArrayList([]const u8),
        };
    }
};

/// description information for a single command
pub const CommandDescription = struct {
    command_sequence: []const u8,
    line: []const u8,
    full: []const u8,
};

/// configuration options for the library
pub const Configuration = struct {
    max_commands: usize = 64,
    max_subcommands: usize = 16,
    /// command description data for commands with no explicit endpoint
    command_descriptions: []const CommandDescription = &.{},
    /// how to handle the case where a command has descriptions defined
    /// in both an endpoint type and in the `command_descriptions` config
    /// field. see `parsley.CommandDescriptionResolution`
    command_description_resolution: CommandDescriptionResolution = .emit_error,
};

/// how to handle the case where a command has descriptions defined
/// in both an endpoint type and in the `command_descriptions` config
/// field. see `parsley.Configuration`
/// * prefer_external : use descriptions defined in config
/// * prefer_internal : use descriptions defined in endpoint
/// * emit_error : produce a compile error
pub const CommandDescriptionResolution = enum {
    prefer_external,
    prefer_internal,
    emit_error,
};

/// parse the commandline calling the specified endpoint
pub fn parse(writer: anytype, comptime endpoints: []const type, comptime config: Configuration) !void {
    comptime if (!std.meta.trait.isPtrTo(.Struct)(@TypeOf(writer))) {
        @compileError("expected pointer to struct, found " ++ @typeName(@TypeOf(writer)));
    };
    comptime if (!std.meta.trait.hasDecls(std.meta.Child(@TypeOf(writer)), .{
        "write",
        "writeAll",
        "print",
        "writeByte",
        "writeByteNTimes",
    })) {
        @compileError("expected writer type, found " ++ @typeName(@TypeOf(writer)));
    };
    const Writer = std.meta.Child(@TypeOf(writer));

    // TODO: verify no duplicate endpoints
    // TODO: verify congig
    // TODO: separate verification into seperate fn
    inline for (endpoints) |e| {
        comptime verifyEndpoint(Writer, e);
    }

    const subcommand_data_buffer = comptime blk: {
        var commandCounts = CommandCounts(endpoints, config.max_commands, config.max_subcommands) catch |err| {
            @compileError("Could not generate command count data: " ++ @errorName(err));
        };
        var buffer: SubcommandDataBuffer(&commandCounts) = undefined;
        inline for (commandCounts.kvSlice()) |*kv| {
            inline for (kv[1].kvSlice(), 0..) |k, i| {
                @field(buffer, kv[0])[i] = k[0];
            }
        }
        break :blk buffer;
    };
    const subcommands = comptime SubcommandMap(&subcommand_data_buffer) catch |err| {
        @compileError("Could not generate subcommand map: " ++ @errorName(err));
    };
    const line_descs = comptime LineDescMap(endpoints, config) catch |err| {
        @compileError("could not generate line description map" ++ @errorName(err));
    };
    const full_descs = comptime FullDescMap(endpoints, config) catch |err| {
        @compileError("could not generate full description map" ++ @errorName(err));
    };

    const parse_fns = comptime ParseFnMap(Writer, endpoints);
    _ = parse_fns;
    const help_fns = comptime HelpFnMap(Writer, full_descs, line_descs, subcommands);

    inline for (help_fns.kvs) |kv| {
        kv.value(writer);
        writer.writeByte('\n') catch {};
    }
}

/// generate a std.ComptimeStringMap that maps commands to
/// a slice of sub commands
fn SubcommandMap(comptime data_buffer: anytype) !type {
    const fields = std.meta.fields(@TypeOf(data_buffer.*));
    var builder = ComptimeStringMapBuilder(fields.len, []const []const u8){};
    inline for (fields) |f| {
        try builder.put(f.name, &@field(data_buffer, f.name));
    }
    return builder.ComptimeStringMap();
}

/// return a std.ComptimeStringMap([]const u8,...) mapping commands to line descriptions
fn LineDescMap(comptime endpoints: []const type, comptime config: Configuration) !type {
    return DescMapImpl(endpoints, config, "description_line", "line");
}

/// return a std.ComptimeStringMap([]const u8,...) mapping commands to full descriptions
fn FullDescMap(comptime endpoints: []const type, comptime config: Configuration) !type {
    return DescMapImpl(endpoints, config, "description_full", "full");
}

fn DescMapImpl(
    comptime endpoints: []const type,
    comptime config: Configuration,
    comptime endpoint_field: []const u8,
    comptime command_description_field: []const u8,
) !type {
    const capacity = endpoints.len + config.command_descriptions.len;
    var builder = ComptimeStringMapBuilder(capacity, []const u8){};
    // note endpoints and config.command_descriptions have been
    // vetted of duplicates
    for (endpoints) |endpoint| {
        try builder.put(endpoint.command_sequence, @field(endpoint, endpoint_field));
    }
    for (config.command_descriptions) |desc| {
        const result = builder.find(desc.command_sequence);
        if (result.found) switch (config.command_description_resolution) {
            .prefer_external => try builder.putFromResults(desc.command_sequence, @field(desc, command_description_field), result),
            .prefer_internal => {},
            .emit_error => @compileError("slut"),
        } else {
            try builder.putFromResults(desc.command_sequence, @field(desc, command_description_field), result);
        }
    }
    return builder.ComptimeStringMap();
}

fn ParseFnMap(comptime Writer: type, comptime endpoints: []const type) type {
    const ParseFn = *const fn (*Writer, []const u8) void;
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
        pub fn parse(writer: *Writer, args: []const u8) void {
            _ = args;
            // TODO: parse from commandline
            var values: Options(cmd.options) = undefined;
            var positionals: Positionals(cmd.positionals) = undefined;
            cmd.run(writer, positionals, values);
        }
    }.parse;
}

fn HelpFnMap(
    comptime Writer: type,
    comptime full_descs: type,
    comptime line_descs: type,
    comptime subcommands: type,
) type {
    const HelpFn = *const fn (*Writer) void;
    const HelpFnKV = struct { []const u8, HelpFn };
    var help_fn_arr: [subcommands.kvs.len]HelpFnKV = undefined;
    inline for (subcommands.kvs, 0..) |kv, i| {
        help_fn_arr[i][0] = kv.key;
        help_fn_arr[i][1] = generateHelpFunction(
            Writer,
            HelpFn,
            kv.key,
            full_descs,
            line_descs,
            subcommands,
        );
    }
    return std.ComptimeStringMap(HelpFn, help_fn_arr);
}

fn generateHelpFunction(
    comptime Writer: type,
    comptime HelpFn: type,
    comptime cmd_sequence: []const u8,
    comptime full_descs: type,
    comptime line_descs: type,
    comptime subcommands: type,
) HelpFn {
    _ = full_descs;
    _ = subcommands;
    return struct {
        pub fn help(writer: *Writer) void {
            const line_desc = line_descs.get(cmd_sequence) orelse "<NOP>";
            writer.print("{s} : {s}", .{ cmd_sequence, line_desc }) catch {};
        }
    }.help;
}

pub fn Positionals(comptime positionals: []const Argument) type {
    return ArgumentTuple(positionals);
}

/// return a struct type with a field for every `Option` in the
/// *options* array. Field names will use the Option's name,
/// field types will use the result of calling `ArgumentTuple()` on
/// the Option's *arguments* field
pub fn Options(comptime options: []const Option) type {
    var fields: [options.len]std.builtin.Type.StructField = undefined;
    inline for (options, 0..) |opt, i| {
        @setEvalBranchQuota(2_000);
        const @"type" = if (opt.arguments.len == 0)
            bool
        else if (opt.arguments.len == 1)
            opt.arguments[0].Type()
        else
            ArgumentTuple(opt.arguments);
        fields[i] = .{
            .name = opt.name,
            .type = @"type",
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(@"type") > 0) @alignOf(@"type") else 0,
        };
    }
    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &.{},
            .fields = &fields,
        },
    });
}

/// return a tuple struct defined by *arguments* array
/// return void if *arguments*.len is 0
/// return single type if *arguments*.len is 1
fn ArgumentTuple(comptime arguments: []const Argument) type {
    if (arguments.len == 0)
        return void
    else if (arguments.len == 1)
        return arguments[0].Type()
    else {
        var types: [arguments.len]type = undefined;
        inline for (arguments, 0..) |v, i| {
            types[i] = v.Type();
        }
        return std.meta.Tuple(&types);
    }
}

/// return a std.ComptimeStringMap() mapping commands to
/// their number of sub commands
fn CommandCounts(
    comptime endpoints: []const type,
    comptime max_commands: usize,
    comptime max_subcommands: usize,
) !ComptimeStringMapBuilder(max_commands, ComptimeStringMapBuilder(max_subcommands, void)) {
    comptime {
        @setEvalBranchQuota(8000);
        var subcounts = ComptimeStringMapBuilder(max_commands, ComptimeStringMapBuilder(max_subcommands, void)){};
        const root_idx = subcounts.find("");
        try subcounts.putFromResults("", ComptimeStringMapBuilder(max_subcommands, void){}, root_idx);

        inline for (endpoints) |e| {
            if (e.command_sequence.len == 0)
                continue;
            var i: usize = 0;
            var command: []const u8 = "";
            var prev_idx = root_idx.index;
            while (i < e.command_sequence.len) : (i += 1) {
                while (i < e.command_sequence.len and e.command_sequence[i] != ' ')
                    i += 1;

                command = e.command_sequence[0..i];

                // count sub command
                try subcounts.value_buffer[subcounts.index_buffer[prev_idx]][1].put(command, {});

                const find_results = subcounts.find(command);
                prev_idx = find_results.index;

                if (!find_results.found) {
                    try subcounts.putFromResults(
                        command,
                        ComptimeStringMapBuilder(max_subcommands, void){},
                        find_results,
                    );
                }
            }
        }
        return subcounts;
    }
}

/// generate a struct with fileds for every command, type is an
/// array of slices. `command_counts` is a std.ComptimeStringMap
/// mapping commands to the number of subcommands
fn SubcommandDataBuffer(comptime command_counts: anytype) type {
    var fields: [command_counts.len]std.builtin.Type.StructField = undefined;
    inline for (command_counts.kvSlice(), 0..) |kv, i| {
        @setEvalBranchQuota(2_000);
        const @"type": type = [kv[1].len][]const u8;
        fields[i] = .{
            .name = kv[0],
            .type = @"type",
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(@"type") > 0) @alignOf(@"type") else 0,
        };
    }
    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &.{},
            .fields = &fields,
        },
    });
}

/// ensure the given type meets the constraints
/// to be an endpoint struct, emmits a compile error otherwise
fn verifyEndpoint(comptime Writer: type, comptime endpoint: type) void {
    comptime {
        verifyStringDeclaration(endpoint, "command_sequence");
        verifyStringDeclaration(endpoint, "description_line");
        verifyStringDeclaration(endpoint, "description_full");
        verifyArrayDeclaration(endpoint, "options", Option);
        verifyArrayDeclaration(endpoint, "positionals", Argument);
        // TODO: verify argument lists, list args must be lonely

        if (!@hasDecl(endpoint, "run"))
            @compileError("Endpoint '" ++ @typeName(endpoint) ++
                "' missing public declaration 'run', should be 'null' or " ++
                "'fn(parsley.Positionals(positionals),parsley.Options(options))void'")
        else if (std.meta.trait.hasFn("run")(endpoint)) {
            const info = @typeInfo(@TypeOf(endpoint.run));
            if (info.Fn.return_type != void)
                @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected return value of 'void'");
            if (info.Fn.params.len != 3)
                @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected three parameters" ++
                    "parsley.Positionals(positionals), and parsley.Options(options)");
            if (info.Fn.params[0].type != *Writer)
                @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected first parameter" ++
                    " of '" ++ @typeName(*Writer) ++ "'" ++ " found: " ++ @typeName(info.Fn.params[0].type orelse void));
            if (info.Fn.params[1].type != Positionals(endpoint.positionals))
                @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected second parameter" ++
                    " of 'parsley.Positionals(positionals)'");
            if (info.Fn.params[2].type != Options(endpoint.options))
                @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected third parameter" ++
                    " of 'parsley.Options(options)'");
        } else if (@TypeOf(endpoint.run) != @TypeOf(null))
            @compileError("Endpoint '" ++ @typeName(endpoint) ++
                " declaration 'run' expected 'null' or 'fn(Writer,parsley.Positionals(positionals),parsley.Options(options))void'");
    }
}

/// emmits a compile error if the endpoint type does not contain a string declaration
/// with the given name
fn verifyStringDeclaration(comptime endpoint: type, comptime name: []const u8) void {
    const string_slice: []const u8 = "";
    if (!std.meta.trait.is(.Struct)(endpoint))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint, name))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' missing public declaration '" ++ name ++ ": []const u8'")
    else if (@TypeOf(@field(endpoint, name), string_slice) != []const u8)
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' declaration '" ++ name ++ "' incorrect type '" ++
            @typeName(@TypeOf(@field(endpoint, name))) ++ "', should be '[]const u8'");
}

/// emmits a compile error if the endpoint type does not contain a array declaration
/// with the given name
fn verifyArrayDeclaration(comptime endpoint: type, comptime name: []const u8, comptime child_type: type) void {
    const child_slice: []const child_type = &.{};
    if (!std.meta.trait.is(.Struct)(endpoint))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint, name))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' missing public declaration '" ++ name ++ ": []const " ++ @typeName(child_type) ++ "'")
    else if (@TypeOf(@field(endpoint, name), child_slice) != @TypeOf(child_slice))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' declaration '" ++ name ++ "' incorrect type '" ++
            @typeName(@TypeOf(@field(endpoint, name))) ++ "', should be '[]const " ++
            @typeName(child_type) ++ "'");
}

test {}
