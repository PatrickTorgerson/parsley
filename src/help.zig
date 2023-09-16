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
                writer.writeAll("\n") catch {};
            }
            const commands = ctx.subcommands.get(command_sequence).?;
            if (commands.len > 0) {
                writer.print("{s} {s} <COMMAND>\n", .{ exename, command_sequence }) catch {};
            }

            const description = ctx.full_descs.get(command_sequence) orelse "";
            writer.print("\n{s}\n\n", .{description}) catch {};

            if (commands.len > 0) {
                writer.print(ctx.config.help_header_fmt, .{"COMMANDS"}) catch {};
                for (commands) |cmd| {
                    const line_desc = ctx.line_descs.get(cmd) orelse "";
                    writer.print("  {s},  {s}\n", .{ cmd[command_sequence.len..], line_desc }) catch {};
                }
                writer.writeAll("\n") catch {};
            }

            if (endpoint != void and endpoint.options.len > 0) {
                writer.print(ctx.config.help_header_fmt, .{"OPTIONS"}) catch {};
                inline for (endpoint.options) |opt| {
                    writeOptionSigniture(ctx, writer, opt) catch {};
                    writer.print(ctx.config.help_option_description_fmt, .{opt.description}) catch {};
                }
                writer.writeAll("\n") catch {};
            }
        }
    }.help;
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
    try writer.print("{s} {s}", .{ exename, endpoint.command_sequence });
    if (endpoint.options.len > 0)
        try writer.writeAll(" [OPTIONS]");
    for (endpoint.positionals) |p| {
        if (p[1].isOptional())
            try writer.print(" [{s}:{s}]", .{ p[0], @tagName(p[1].scalar()) })
        else
            try writer.print(" <{s}:{s}>", .{ p[0], @tagName(p[1].scalar()) });
    }
}

fn EndpointOrVoid(comptime endpoints: []const type, comptime command_sequence: []const u8) type {
    inline for (endpoints) |endpoint| {
        if (std.mem.eql(u8, endpoint.command_sequence, command_sequence))
            return endpoint;
    }
    return void;
}
