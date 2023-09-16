// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const common = @import("common.zig");
const Option = common.Option;
const Context = common.Context;
const Configuration = common.Configuration;

pub const help_help_desc = "Show info on a specific command or topic";

pub fn FunctionMap(comptime ctx: Context) type {
    const HelpFn = *const fn (*ctx.WriterType, []const u8) void;
    const HelpFnKV = struct { []const u8, HelpFn };
    var help_fn_arr: [ctx.subcommands.kvs.len]HelpFnKV = undefined;
    inline for (ctx.subcommands.kvs, 0..) |kv, i| {
        help_fn_arr[i][0] = kv.key;
        help_fn_arr[i][1] = generateHelpFunction(
            ctx,
            EndpointOrVoid(ctx.endpoints, kv.key),
            HelpFn,
            kv.key,
        );
    }
    return std.ComptimeStringMap(HelpFn, help_fn_arr);
}

fn generateHelpFunction(
    comptime ctx: Context,
    comptime endpoint: type,
    comptime HelpFn: type,
    comptime command_sequence: []const u8,
) HelpFn {
    return struct {
        pub fn help(writer: *ctx.WriterType, exename: []const u8) void {
            if (endpoint != void) {
                writeUsage(ctx, endpoint, exename, writer) catch {};
                writer.writeByte('\n') catch {};
            }
            const commands = ctx.subcommands.get(command_sequence).?;
            if (commands.len > 0) {
                writer.print(" $ {s} {s} <COMMAND>\n", .{ exename, command_sequence }) catch {};
            }

            const description = ctx.full_descs.get(command_sequence) orelse "";
            writer.print("\n{s}\n\n", .{description}) catch {};

            if (commands.len > 0) {
                writer.print(ctx.config.help_header_fmt, .{"COMMANDS"}) catch {};
                for (commands) |command| {
                    const line_desc = ctx.line_descs.get(command) orelse "";
                    writer.print("  {s},  {s}\n", .{ command[command_sequence.len..], line_desc }) catch {};
                }
                writer.writeByte('\n') catch {};
            }

            if (endpoint != void and endpoint.options.len > 0) {
                writer.print(ctx.config.help_header_fmt, .{"OPTIONS"}) catch {};
                inline for (endpoint.options) |opt| {
                    writeOptionSigniture(ctx, writer, opt) catch {};
                    writer.print(ctx.config.help_option_description_fmt, .{opt.description}) catch {};
                }
                writer.writeByte('\n') catch {};
            }
        }
    }.help;
}

/// Implementation for the builtin help command
pub fn cmd(
    comptime ctx: Context,
    comptime help_fns: type,
    allocator: std.mem.Allocator,
    writer: *ctx.WriterType,
    exename: []const u8,
    first_arg: ?[]const u8,
    args: *std.process.ArgIterator,
) !void {
    if (first_arg == null) {
        help_fns.get("").?(writer, exename);
        return;
    }

    if (std.mem.eql(u8, first_arg.?, "help") or
        std.mem.eql(u8, first_arg.?, "--help") or
        std.mem.eql(u8, first_arg.?, "-help") or
        std.mem.eql(u8, first_arg.?, "--h") or
        std.mem.eql(u8, first_arg.?, "-h") or
        std.mem.eql(u8, first_arg.?, "--H") or
        std.mem.eql(u8, first_arg.?, "-H") or
        std.mem.eql(u8, first_arg.?, "--?") or
        std.mem.eql(u8, first_arg.?, "-?"))
    {
        writeHelpHelp(ctx, exename, writer) catch {};
        return;
    }

    var argbuf = std.ArrayListUnmanaged(u8){};
    defer argbuf.deinit(allocator);

    var next_arg = first_arg;
    while (next_arg) |arg| : (next_arg = args.next()) {
        try argbuf.appendSlice(allocator, arg);
        try argbuf.append(allocator, ' ');
    }
    // remove trailing space
    argbuf.items.len -= 1;

    if (ctx.subcommands.has(argbuf.items)) {
        help_fns.get(argbuf.items).?(writer, exename);
    } else {
        inline for (ctx.config.help_topics) |topic| {
            if (std.mem.eql(u8, topic.name, argbuf.items)) {
                writer.writeAll(topic.body) catch {};
                writer.writeByte('\n') catch {};
                return;
            }
        }
    }

    writer.print(
        " '{s}' is not a command or topic\n to see a list of available topics use '{s} help --help'\n",
        .{ argbuf.items, exename },
    ) catch {};
}

/// write option names and arguments
pub fn writeOptionSigniture(comptime ctx: Context, writer: *ctx.WriterType, opt: Option) !void {
    writer.print(" --{s}", .{opt.name}) catch {};
    if (opt.name_short) |short| {
        writer.print(", -{c}", .{short}) catch {};
    }
    if (opt.arguments.len > 0) {
        writer.writeAll(" : ") catch {};
        for (opt.arguments) |arg| {
            writer.print(ctx.config.help_option_argument_fmt, .{@tagName(arg)}) catch {};
        }
    }
}

pub fn writeUsage(
    comptime ctx: Context,
    comptime endpoint: type,
    exename: []const u8,
    writer: *ctx.WriterType,
) !void {
    try writer.print(" $ {s} {s}", .{ exename, endpoint.command_sequence });
    if (endpoint.options.len > 0)
        try writer.writeAll(" [OPTIONS]");
    for (endpoint.positionals) |p| {
        if (p[1].isOptional())
            try writer.print(" [{s}:{s}]", .{ p[0], @tagName(p[1].scalar()) })
        else
            try writer.print(" <{s}:{s}>", .{ p[0], @tagName(p[1].scalar()) });
    }
}

fn writeHelpHelp(
    comptime ctx: Context,
    exename: []const u8,
    writer: *ctx.WriterType,
) !void {
    try writer.print(" $ {s} help <COMMAND>\n", .{exename});
    try writer.print(" $ {s} help <TOPIC>\n\n{s}\n\n", .{ exename, help_help_desc });
    if (ctx.config.help_topics.len > 0) {
        try writer.print(ctx.config.help_header_fmt, .{"TOPICS"});
        inline for (ctx.config.help_topics) |topic| {
            try writer.print("  {s},  {s}\n", .{ topic.name, topic.desc });
        }
        try writer.writeByte('\n');
    }
    if (ctx.subcommands.kvs.len > 1) {
        try writer.print(ctx.config.help_header_fmt, .{"COMMANDS"});
        inline for (ctx.subcommands.kvs[1..]) |kv| {
            try writer.print("  {s}\n", .{kv.key});
        }
        try writer.writeByte('\n');
    }
}

fn EndpointOrVoid(comptime endpoints: []const type, comptime command_sequence: []const u8) type {
    inline for (endpoints) |endpoint| {
        if (std.mem.eql(u8, endpoint.command_sequence, command_sequence))
            return endpoint;
    }
    return void;
}
