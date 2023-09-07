// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const common = @import("common.zig");
const Option = common.Option;
const Positional = common.Positional;
const Argument = common.Argument;
const CommandDescription = common.CommandDescription;
const Positionals = common.Positionals;
const Options = common.Options;
const ArgumentTuple = common.ArgumentTuple;

/// verify all endpoints are unique and valid
pub fn endpoints(comptime endpoints_: []const type, comptime writer: type) void {
    // TODO: verify no duplicate endpoints
    inline for (endpoints_) |e| {
        comptime endpoint(e, writer);
    }
}

// verify config is valid
pub fn config(comptime config_: anytype) void {
    _ = config_;
    // TODO: verify command_descriptions are unique
}

/// verify `writer` is a valid ptr to a writer type
/// return the writer type
pub fn Writer(comptime writer: type) type {
    comptime {
        if (!std.meta.trait.isPtrTo(.Struct)(writer)) {
            @compileError("expected pointer to struct, found " ++ @typeName(writer));
        }
        const WriterTy = std.meta.Child(writer);
        if (!std.meta.trait.hasDecls(WriterTy, .{
            "write",
            "writeAll",
            "print",
            "writeByte",
            "writeByteNTimes",
        })) {
            @compileError("expected writer type, found " ++ @typeName(writer));
        }
        return WriterTy;
    }
}

/// verify the given type meets the constraints
/// to be an endpoint struct, emmits a compile error otherwise
pub fn endpoint(comptime endpoint_: type, comptime writer: type) void {
    comptime {
        stringDeclaration(endpoint_, "command_sequence");
        stringDeclaration(endpoint_, "description_line");
        stringDeclaration(endpoint_, "description_full");
        arrayDeclaration(endpoint_, "options", Option);
        arrayDeclaration(endpoint_, "positionals", Positional);
        runFunction(endpoint_, writer);
        // TODO: verify argument lists, list args must be lonely
        // TODO: verify command sequence

    }
}

/// verify endpoint's run function has the correct signiture
/// `fn(writer,Positionals,Options) anytype!void`
pub fn runFunction(comptime endpoint_: type, comptime writer: type) void {
    if (!@hasDecl(endpoint_, "run"))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' missing public declaration 'run', should be 'null' or " ++
            "'fn(parsley.Positionals(positionals),parsley.Options(options))void'")
    else if (std.meta.trait.hasFn("run")(endpoint_)) {
        const info = @typeInfo(@TypeOf(endpoint_.run));
        if (info.Fn.return_type != anyerror!void)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "' declaration 'run' expected return value of 'anyerror!void' found '" ++ @typeName(info.Fn.return_type orelse noreturn) ++ "'");
        if (info.Fn.params.len != 3)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected three parameters" ++
                "parsley.Positionals(positionals), and parsley.Options(options)");
        if (info.Fn.params[0].type != *writer)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected first parameter" ++
                " of '" ++ @typeName(*writer) ++ "'" ++ " found: " ++ @typeName(info.Fn.params[0].type orelse void));
        if (info.Fn.params[1].type != Positionals(endpoint_.positionals))
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected second parameter" ++
                " of 'parsley.Positionals(positionals)'");
        if (info.Fn.params[2].type != Options(endpoint_.options))
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected third parameter" ++
                " of 'parsley.Options(options)'");
    } else if (@TypeOf(endpoint_.run) != @TypeOf(null))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            " declaration 'run' expected 'null' or 'fn(Writer,parsley.Positionals(positionals),parsley.Options(options))void'");
}

/// emmits a compile error if the endpoint type does not contain a string declaration
/// with the given name
pub fn stringDeclaration(comptime endpoint_: type, comptime name: []const u8) void {
    const string_slice: []const u8 = "";
    if (!std.meta.trait.is(.Struct)(endpoint_))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint_, name))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' missing public declaration '" ++ name ++ ": []const u8'")
    else if (@TypeOf(@field(endpoint_, name), string_slice) != []const u8)
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' declaration '" ++ name ++ "' incorrect type '" ++
            @typeName(@TypeOf(@field(endpoint_, name))) ++ "', should be '[]const u8'");
}

/// emmits a compile error if the endpoint type does not contain a array declaration
/// with the given name
pub fn arrayDeclaration(comptime endpoint_: type, comptime name: []const u8, comptime child_type: type) void {
    const child_slice: []const child_type = &.{};
    _ = child_slice;
    if (!std.meta.trait.is(.Struct)(endpoint_))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint_, name))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' missing public declaration '" ++ name ++ ": []const " ++ @typeName(child_type) ++ "'")
    else if (!std.meta.trait.isPtrTo(.Array)(@TypeOf(@field(endpoint_, name))))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' incorrect type; expected '[]const " ++ @typeName(child_type) ++
            "' but found '" ++ @typeName(@TypeOf(@field(endpoint_, name))))
    else if (std.meta.Child(std.meta.Child(@TypeOf(@field(endpoint_, name)))) != child_type)
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' incorrect type; expected '[]const " ++ @typeName(child_type) ++
            "' but found '" ++ @typeName(@TypeOf(@field(endpoint_, name))));
}
