// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2024 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const common = @import("common.zig");
const EmptyComptimeStringMap = common.EmptyComptimeStringMap;

/// helper type that allows programatically building the contents of
/// a std.ComptimeStringMap at compile time.
/// use `put()` to add values, call `ComptimeStringMap()` to convert to std.ComptimeStringMap
/// **capacity:** size of internal buffers
/// **V:** value type
pub fn ComptimeStringMapBuilder(comptime capacity: usize, comptime V: type) type {
    return struct {
        pub const KV = struct { []const u8, V };

        pub const FindResult = struct {
            found: bool,
            index: usize,
        };

        const empty = std.math.maxInt(usize);

        index_buffer: [capacity]usize = [_]usize{empty} ** capacity,
        value_buffer: [capacity]KV = undefined,
        len: usize = 0,

        pub fn has(comptime this: *@This(), comptime key: []const u8) bool {
            const result = this.find(key);
            return result.found;
        }

        pub fn put(
            comptime this: *@This(),
            comptime key: []const u8,
            comptime value: V,
        ) error{out_of_memory}!void {
            const result = this.find(key);
            return putFromResults(this, key, value, result);
        }

        pub fn putFromResults(
            comptime this: *@This(),
            comptime key: []const u8,
            comptime value: V,
            comptime result: FindResult,
        ) error{out_of_memory}!void {
            if (result.found) {
                const index = this.index_buffer[result.index];
                this.value_buffer[index][1] = value;
            } else {
                if (this.index_buffer[result.index] != empty)
                    return error.out_of_memory;
                this.index_buffer[result.index] = this.len;
                this.value_buffer[this.len][0] = key;
                this.value_buffer[this.len][1] = value;
                this.len += 1;
            }
        }

        pub fn get(comptime this: *@This(), comptime key: []const u8) ?*V {
            const result = this.find(key);
            return this.getFromResult(result);
        }

        pub fn getFromResult(
            comptime this: *@This(),
            comptime result: FindResult,
        ) ?*V {
            return if (result.found)
                &this.value_buffer[this.index_buffer[result.index]][1]
            else
                null;
        }

        pub fn kvSlice(comptime this: *@This()) []KV {
            return this.value_buffer[0..this.len];
        }

        pub fn kvSliceConst(comptime this: @This()) []const KV {
            return this.value_buffer[0..this.len];
        }

        pub fn ComptimeStringMap(comptime this: *@This()) type {
            return if (this.len > 0)
                common.ComptimeStringMap(V, this.kvSlice())
            else
                EmptyComptimeStringMap(V);
        }

        pub fn find(comptime this: *@This(), comptime key: []const u8) FindResult {
            const start = indexStart(key);

            if (this.index_buffer[start] == empty) {
                return .{ .found = false, .index = start };
            }

            if (std.mem.eql(u8, key, this.value_buffer[this.index_buffer[start]][0])) {
                return .{ .found = true, .index = start };
            }

            var index = (start + 1) % capacity;
            while (index != start and this.index_buffer[index] != empty) {
                if (std.mem.eql(u8, key, this.value_buffer[this.index_buffer[index]][0])) {
                    return .{ .found = true, .index = index };
                }
                index = (index + 1) % capacity;
            }

            return .{ .found = false, .index = index };
        }

        fn indexStart(comptime key: []const u8) usize {
            const hash = std.hash.Wyhash.hash(0, key);
            return @intCast(hash % capacity);
        }
    };
}

test "ComptimeStringMapBuilder - put() and has()" {
    const flags = comptime blk: {
        var builder = ComptimeStringMapBuilder(16, u8){};
        try builder.put("one", 1);
        try builder.put("two", 2);
        try builder.put("three", 3);
        try builder.put("four", 4);

        break :blk .{
            .has_one = builder.has("one"),
            .has_two = builder.has("two"),
            .has_three = builder.has("three"),
            .has_four = builder.has("four"),
            .has_five = builder.has("five"),
            .has_six = builder.has("six"),
        };
    };

    try std.testing.expect(flags.has_one);
    try std.testing.expect(flags.has_two);
    try std.testing.expect(flags.has_three);
    try std.testing.expect(flags.has_four);
    try std.testing.expect(!flags.has_five);
    try std.testing.expect(!flags.has_six);
}

test "ComptimeStringMapBuilder - get()" {
    const values = comptime blk: {
        var builder = ComptimeStringMapBuilder(16, u8){};
        try builder.put("one", 1);
        try builder.put("two", 2);
        try builder.put("three", 3);
        try builder.put("four", 4);

        const launder = struct {
            fn launder(ptr: ?*u8) ?u8 {
                return if (ptr) |p|
                    p.*
                else
                    null;
            }
        }.launder;

        break :blk .{
            .one = launder(builder.get("one")),
            .two = launder(builder.get("two")),
            .three = launder(builder.get("three")),
            .four = launder(builder.get("four")),
            .five = launder(builder.get("five")),
            .six = launder(builder.get("six")),
        };
    };

    try std.testing.expectEqual(@as(?u8, 1), values.one);
    try std.testing.expectEqual(@as(?u8, 2), values.two);
    try std.testing.expectEqual(@as(?u8, 3), values.three);
    try std.testing.expectEqual(@as(?u8, 4), values.four);
    try std.testing.expectEqual(@as(?u8, null), values.five);
    try std.testing.expectEqual(@as(?u8, null), values.six);
}
