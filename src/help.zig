// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub fn FunctionMap(
    comptime WriterType: type,
    comptime endpoints: []const type,
    comptime full_descs: type,
    comptime line_descs: type,
    comptime subcommands: type,
) type {
    const HelpFn = *const fn (*WriterType) void;
    const HelpFnKV = struct { []const u8, HelpFn };
    var help_fn_arr: [subcommands.kvs.len]HelpFnKV = undefined;
    inline for (subcommands.kvs, 0..) |kv, i| {
        help_fn_arr[i][0] = kv.key;
        help_fn_arr[i][1] = generateHelpFunction(
            WriterType,
            EndpointOrVoid(endpoints, kv.key),
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
    comptime WriterType: type,
    comptime endpoint: type,
    comptime HelpFn: type,
    comptime command_sequence: []const u8,
    comptime full_descs: type,
    comptime line_descs: type,
    comptime subcommands: type,
) HelpFn {
    return struct {
        pub fn help(writer: *WriterType) void {
            const description = full_descs.get(command_sequence) orelse "<NOP>";
            writer.print("\n{s}\n\n", .{description}) catch {};

            // TODO: usage

            const commands = subcommands.get(command_sequence).?;
            if (commands.len > 0) {
                writer.writeAll("COMMANDS\n") catch {};
                for (commands) |cmd| {
                    const line_desc = line_descs.get(cmd) orelse "";
                    writer.print("  {s},  {s}\n", .{ cmd[command_sequence.len..], line_desc }) catch {};
                }
                writer.writeAll("\n") catch {};
            }

            if (endpoint != void and endpoint.options.len > 0) {
                writer.writeAll("OPTIONS\n") catch {};
                inline for (endpoint.options) |opt| {
                    writer.print(" --{s}", .{opt.name}) catch {};
                    if (opt.name_short) |short| {
                        writer.print(", -{c} : ", .{short}) catch {};
                    } else writer.writeAll("       ") catch {};
                    inline for (opt.arguments) |arg| {
                        writer.print("{s} ", .{@tagName(arg)}) catch {};
                    }
                    writer.print("\n    {s}\n", .{opt.description}) catch {};
                }
                writer.writeAll("\n") catch {};
            }
        }
    }.help;
}

fn EndpointOrVoid(comptime endpoints: []const type, comptime command_sequence: []const u8) type {
    inline for (endpoints) |endpoint| {
        if (std.mem.eql(u8, endpoint.command_sequence, command_sequence))
            return endpoint;
    }
    return void;
}