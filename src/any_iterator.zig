// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2024 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const assert = std.debug.assert;

/// type-erased interface for all iterator types
pub fn AnyIterator(comptime T: type) type {
    return struct {
        /// pointer to underlying iterator
        ptr: *anyopaque,
        /// pointer to next function
        nextfn: *const fn (*anyopaque) ?T,

        /// create from pointer to iterator and next fn
        /// expected signiture of nextfn `fn(self: @TypeOf(pointer)) ?T`
        pub fn initWithNextFn(pointer: anytype, nextfn: anytype) @This() {
            const Ptr = @TypeOf(pointer);
            const proxy = struct {
                fn next_proxy(ptr: *anyopaque) ?T {
                    const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                    return @call(.always_inline, nextfn, .{self});
                }
            };
            return .{
                .ptr = pointer,
                .nextfn = proxy.next_proxy,
            };
        }

        /// create from pointer to iterator, looks for decl `next()` as nextfn
        /// expected signiture of nextfn `fn(self: @TypeOf(pointer)) ?T`
        pub fn init(pointer: anytype) @This() {
            const ptr_info = @typeInfo(@TypeOf(pointer));
            const Child = ptr_info.Pointer.child;
            return @This().initWithNextFn(pointer, @field(Child, "next"));
        }

        /// return next element in sequence, null if no elements remain
        pub fn next(self: @This()) ?T {
            return self.nextfn(self.ptr);
        }
    };
}
