// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const ComptimeStringMapBuilder = @import("comptimestringmapbuilder.zig").ComptimeStringMapBuilder;

const parse = @import("parse.zig");
const help = @import("help.zig");
const verify = @import("verify.zig");
const common = @import("common.zig");

pub const Option = common.Option;
pub const Positional = common.Positional;
pub const Argument = common.Argument;
pub const CommandDescription = common.CommandDescription;
pub const Positionals = common.Positionals;
pub const Options = common.Options;
pub const ArgumentTuple = common.ArgumentTuple;

/// configuration options for the library
pub const Configuration = struct {
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

pub const Writer = @TypeOf(std.io.getStdOut().writer());
pub const BufferedWriter = std.io.BufferedWriter(4096, Writer).Writer;

/// parse the commandline, calling the specified endpoint
pub fn run(allocator: std.mem.Allocator, writer: anytype, comptime endpoints: []const type, comptime config: Configuration) !void {
    const WriterType = comptime verify.Writer(@TypeOf(writer));
    comptime verify.endpoints(endpoints, WriterType);
    comptime verify.config(config);

    const max_commands = comptime determineMaxCommands(endpoints);
    const max_subcommands = endpoints.len;
    const subcommand_data_buffer = comptime blk: {
        var command_counts = commandCounts(endpoints, max_commands, max_subcommands) catch |err| {
            @compileError("Could not generate command count data: " ++ @errorName(err));
        };
        var buffer: SubcommandDataBuffer(&command_counts) = undefined;
        inline for (command_counts.kvSlice()) |*kv| {
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

    const parse_fns = comptime parse.FunctionMap(WriterType, endpoints);
    const help_fns = comptime help.FunctionMap(WriterType, endpoints, full_descs, line_descs, subcommands);

    var argsIter = try std.process.argsWithAllocator(allocator);
    defer argsIter.deinit();
    _ = argsIter.next(); // executable path

    const command = try parseCommandSequence(allocator, &argsIter, subcommands);
    defer allocator.free(command.sequence);

    if (command.next) |next| {
        if (std.mem.eql(u8, next, "--help") or
            std.mem.eql(u8, next, "-help") or
            std.mem.eql(u8, next, "-h") or
            std.mem.eql(u8, next, "-H") or
            std.mem.eql(u8, next, "--h") or
            std.mem.eql(u8, next, "--H"))
        {
            help_fns.get(command.sequence).?(writer);
            return;
        } else if (parse_fns.get(command.sequence)) |parse_fn| {
            try parse_fn(allocator, writer, command.next, &argsIter);
            return;
        } else if (next[0] == '-') {
            help_fns.get(command.sequence).?(writer);
            return;
        } else {
            writer.print("\n'{s}' is not a subcommand of '{s}'\n\n", .{ next, command.sequence }) catch {};
            return;
        }
    } else if (parse_fns.get(command.sequence)) |parse_fn| {
        try parse_fn(allocator, writer, null, &argsIter);
        return;
    } else {
        help_fns.get(command.sequence).?(writer);
        return;
    }
}

/// parse the set of cli args that compose the command sequence
/// redundant whitespace is ignored
/// return two slices, `sequence` and `next`
/// `sequence` is the parsed command sequence, this is garenteed to be a valid command
/// `next` is the next arg on the command line, or null
/// `sequence` must be freed, `next` does not
fn parseCommandSequence(
    allocator: std.mem.Allocator,
    argsIter: *std.process.ArgIterator,
    comptime subcommands: type,
) !struct { sequence: []const u8, next: ?[]const u8 } {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();
    while (argsIter.next()) |arg| {
        const prev_len = buffer.items.len;
        if (buffer.items.len > 0)
            try buffer.append(' ');
        try buffer.appendSlice(arg);
        if (!subcommands.has(buffer.items)) {
            buffer.items.len = prev_len;
            return .{
                .sequence = try buffer.toOwnedSlice(),
                .next = arg,
            };
        }
    }
    return .{
        .sequence = try buffer.toOwnedSlice(),
        .next = null,
    };
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

/// return a std.ComptimeStringMap() mapping commands to
/// their number of sub commands
fn commandCounts(
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

///
fn determineMaxCommands(comptime endpoints: []const type) usize {
    var max_commands = 0;
    inline for (endpoints) |endpoint| {
        max_commands += 1;
        for (endpoint.command_sequence) |char| {
            if (char == ' ')
                max_commands += 1;
        }
    }
    return max_commands;
}

test {}
