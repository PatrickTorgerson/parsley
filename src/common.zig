// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

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

pub const Positional = struct {
    /// name
    []const u8,
    /// argument
    Argument,
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

    pub fn isOptional(this: Argument) bool {
        return switch (this) {
            .integer,
            .floating,
            .boolean,
            .string,
            .integer_list,
            .floating_list,
            .boolean_list,
            .string_list,
            => false,
            .optional_integer,
            .optional_floating,
            .optional_boolean,
            .optional_string,
            => true,
        };
    }

    pub fn isList(this: Argument) bool {
        return switch (this) {
            .integer,
            .floating,
            .boolean,
            .string,
            .optional_integer,
            .optional_floating,
            .optional_boolean,
            .optional_string,
            => false,
            .integer_list,
            .floating_list,
            .boolean_list,
            .string_list,
            => true,
        };
    }
};

/// description information for a single command
pub const CommandDescription = struct {
    command_sequence: []const u8,
    line: []const u8,
    full: []const u8,
};

pub fn Positionals(comptime endpoint: type) type {
    const positionals = endpoint.positionals;
    comptime @import("verify.zig").positionals(endpoint);
    var fields: [positionals.len]std.builtin.Type.StructField = undefined;
    inline for (positionals, 0..) |positional, i| {
        @setEvalBranchQuota(2_000);
        const @"type" = positional[1].Type();
        fields[i] = .{
            .name = positional[0],
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

/// return a struct type with a field for every `Option` in the
/// *options* array. Field names will use the Option's name,
/// field types will use the result of calling `ArgumentTuple()` on
/// the Option's *arguments* field
pub fn Options(comptime endpoint: type) type {
    const options = endpoint.options;
    comptime @import("verify.zig").options(endpoint);
    var fields: [options.len]std.builtin.Type.StructField = undefined;
    inline for (options, 0..) |opt, i| {
        @setEvalBranchQuota(2_000);
        const @"type" = if (opt.arguments.len == 0)
            bool
        else if (opt.arguments.len == 1)
            OptionSingleValueType(opt.arguments[0])
        else
            ?ArgumentTuple(opt.arguments);
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

fn OptionSingleValueType(comptime argument: Argument) type {
    return switch (argument) {
        .integer,
        .floating,
        .boolean,
        .string,
        .integer_list,
        .floating_list,
        .boolean_list,
        .string_list,
        => ?argument.Type(),
        .optional_integer,
        .optional_floating,
        .optional_boolean,
        .optional_string,
        => struct { present: bool, value: argument.Type() },
    };
}

/// return a tuple struct defined by *arguments* array
/// return void if *arguments*.len is 0
/// return single type if *arguments*.len is 1
pub fn ArgumentTuple(comptime arguments: []const Argument) type {
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

/// return a value of struct type `T` with fields set to sane defaults
/// not all types will be initialized, `undefined` is used in
/// those cases, see implementation. default values are honored
pub fn initStructWithDefaults(comptime T: type) T {
    const fill = comptime struct {
        pub fn fill(value: *T) void {
            inline for (std.meta.fields(T)) |f| {
                @field(value, f.name) = if (f.default_value) |v|
                    @as(*const f.type, @ptrCast(v)).*
                else
                    defaultValue(f.type);
            }
        }
        fn defaultValue(comptime V: type) V {
            return switch (@typeInfo(V)) {
                .Int => @intCast(0),
                .Float => @floatCast(0.0),
                .Bool => false,
                .Void => {},
                .Type => void,
                .Optional => null,
                .Null => null,
                .Struct => blk: {
                    if (comptime isSingleOptionalStruct(V)) {
                        break :blk .{ .present = false, .value = null };
                    } else break :blk undefined;
                },
                else => undefined,
            };
        }
    }.fill;
    var t: T = undefined;
    fill(&t);
    return t;
}

pub fn isSingleOptionalStruct(comptime T: type) bool {
    return std.meta.trait.is(.Struct)(T) and
        std.meta.fields(T).len == 2 and
        std.meta.trait.hasFields(T, .{ "present", "value" }) and
        std.meta.fieldInfo(T, std.enums.nameCast(std.meta.FieldEnum(T), "present")).type == bool and
        std.meta.trait.is(.Optional)(std.meta.fieldInfo(T, std.enums.nameCast(std.meta.FieldEnum(T), "value")).type);
}

test "initStructWithDefaults()" {
    const T = struct {
        one: bool,
        two: ?bool,
        three: i32,
        four: i8 = 69,
        five: f16,
    };
    const value = initStructWithDefaults(T);
    try std.testing.expectEqual(@as(bool, false), value.one);
    try std.testing.expectEqual(@as(?bool, null), value.two);
    try std.testing.expectEqual(@as(i32, 0), value.three);
    try std.testing.expectEqual(@as(i8, 69), value.four);
    try std.testing.expectEqual(@as(f16, 0.0), value.five);
}

pub fn EmptyComptimeStringMap(comptime V: type) type {
    return struct {
        pub const kvs = &[_]V{};
        pub fn has(_: []const u8) bool {
            return false;
        }
        pub fn get(_: []const u8) ?V {
            return null;
        }
    };
}
