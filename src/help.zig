// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub fn FunctionMap(
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
    return struct {
        pub fn help(writer: *Writer) void {
            const description = full_descs.get(cmd_sequence) orelse "<NOP>";
            writer.print("\n{s}\n\n", .{description}) catch {};

            const commands = subcommands.get(cmd_sequence).?;
            if (commands.len > 0) {
                writer.writeAll("COMMANDS\n") catch {};
                for (commands) |cmd| {
                    const line_desc = line_descs.get(cmd) orelse "";
                    writer.print("  {s:.<20}: {s}\n", .{ cmd[cmd_sequence.len..], line_desc }) catch {};
                }
            }

            // TODO: options and positionals
        }
    }.help;
}
