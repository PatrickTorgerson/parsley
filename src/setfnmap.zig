// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2024 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const trait = @import("trait.zig");
const common = @import("common.zig");
const Option = common.Option;
const Positional = common.Positional;
const Argument = common.Argument;
const Positionals = common.Positionals;
const Options = common.Options;
const EmptyComptimeStringMap = common.EmptyComptimeStringMap;
const isSingleOptionalStruct = common.isSingleOptionalStruct;

const SetFnError =
    std.fmt.ParseIntError ||
    std.fmt.ParseFloatError ||
    error{ invalid_boolean, invalid_argument_type, OutOfMemory };

/// generate a map type that maps field names to set fns
/// the returned namespace has fn `get(field: []const u8, idx: usize) ?SetFn`
/// where `field` is the field name in `T` and `idx` is a tuple index, if field
/// is not a tuple `idx` should be 0.
///
/// the set fn returned by get() takes the form `fn (a: std.mem.Allocator, t: *T, val: []const u8) !void`
/// where `t` is a pointer to the struct who's field will be set. `val` is the value to set the field to
/// as a string
pub fn SetFnMap(comptime T: type) type {
    const SetFn = *const fn (std.mem.Allocator, *T, []const u8) SetFnError!void;

    const size = countValues(T);
    if (size == 0) return struct {
        pub fn get(_: []const u8, _: usize) ?SetFn {
            return null;
        }
    };

    const SetFnKV = struct { []const u8, SetFn };
    var set_fn_arr: [size]SetFnKV = undefined;

    var i: usize = 0;
    inline for (std.meta.fields(T)) |field| {
        if (trait.is(.optional)(field.type) and trait.isTuple(std.meta.Child(field.type))) {
            inline for (std.meta.fields(std.meta.Child(field.type)), 0..) |tuple_field, tuple_index| {
                set_fn_arr[i][0] = field.name ++ tuple_field.name;
                set_fn_arr[i][1] = generateSetFunction(
                    SetFn,
                    T,
                    field.name,
                    tuple_index,
                    false,
                    tuple_field.type,
                );
                i += 1;
            }
        } else {
            set_fn_arr[i][0] = field.name ++ "0";
            set_fn_arr[i][1] = generateSetFunction(
                SetFn,
                T,
                field.name,
                0,
                true,
                field.type,
            );
            i += 1;
        }
    }
    const fns = common.ComptimeStringMap(SetFn, set_fn_arr);
    const ids = ValueIdentifierMap(T);
    return struct {
        pub fn get(field: []const u8, idx: usize) ?SetFn {
            return fns.get(ids.get(field, idx));
        }
    };
}

/// generate a set function for the given field
fn generateSetFunction(
    comptime SetFn: type,
    comptime options: type,
    comptime field_name: []const u8,
    comptime index: usize,
    comptime single: bool,
    comptime field_type: type,
) SetFn {
    return struct {
        pub fn set(ally: std.mem.Allocator, p: *options, value: []const u8) SetFnError!void {
            if (comptime isSingleOptionalStruct(field_type)) {
                const ValueType = std.meta.fieldInfo(field_type, std.enums.nameCast(std.meta.FieldEnum(field_type), "value")).type;
                @field(p, field_name) = .{
                    .present = true,
                    .value = if (value.len == 0) null else try parseValue(std.meta.Child(ValueType), value),
                };
            } else {
                const T = comptime if (trait.is(.optional)(field_type))
                    std.meta.Child(field_type)
                else
                    field_type;

                if (comptime single) {
                    if (comptime trait.is(.@"struct")(T)) {
                        // ArrayList
                        if (comptime trait.is(.optional)(field_type))
                            try @field(p, field_name).?.append(ally, try parseValue(std.meta.Child(T.Slice), value))
                        else
                            try @field(p, field_name).append(ally, try parseValue(std.meta.Child(T.Slice), value));
                    } else @field(p, field_name) = try parseValue(T, value);
                } else {
                    // tuple
                    @field(p, field_name).?[index] = try parseValue(T, value);
                }
            }
        }
    }.set;
}

/// generate a type to map a field name and index to a field identifier
fn ValueIdentifierMap(comptime T: type) type {
    const precomputed = comptime blk: {
        const size = countValues(T);
        var idbuffer: [size][]const u8 = undefined;
        const KV = struct { []const u8, usize };
        var mappings: [std.meta.fields(T).len]KV = undefined;
        var i: usize = 0;
        for (std.meta.fields(T), 0..) |field, fi| {
            mappings[fi] = .{ field.name, i };
            if (trait.is(.optional)(field.type) and trait.isTuple(std.meta.Child(field.type))) {
                for (std.meta.fields(std.meta.Child(field.type))) |tuple_field| {
                    idbuffer[i] = field.name ++ tuple_field.name;
                    i += 1;
                }
            } else {
                idbuffer[i] = field.name ++ "0";
                i += 1;
            }
        }
        break :blk .{
            .idbuffer = idbuffer,
            .mappings = if (mappings.len > 0)
                common.ComptimeStringMap(usize, mappings)
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

/// counts the numver of values in a struct where each tuple value is counted
fn countValues(comptime T: type) usize {
    return comptime blk: {
        var size: usize = 0;
        for (std.meta.fields(T)) |field| {
            if (trait.is(.optional)(field.type) and trait.isTuple(std.meta.Child(field.type)))
                size += std.meta.fields(std.meta.Child(field.type)).len
            else
                size += 1;
        }
        break :blk size;
    };
}

/// parse string `value` as type `T`
fn parseValue(comptime T: type, value: []const u8) !T {
    return switch (T) {
        i64 => try std.fmt.parseInt(i64, value, 0),
        f64 => try std.fmt.parseFloat(f64, value),
        bool => if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else error.invalid_boolean,
        []const u8 => return value,
        else => error.invalid_argument_type,
    };
}
