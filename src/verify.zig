// ********************************************************************************
//  https://github.com/PatrickTorgerson
//  Copyright (c) 2024 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const ComptimeStringMapBuilder = @import("comptimestringmapbuilder.zig").ComptimeStringMapBuilder;

const trait = @import("trait.zig");
const common = @import("common.zig");
const Option = common.Option;
const Positional = common.Positional;
const Argument = common.Argument;
const CommandDescription = common.CommandDescription;
const Positionals = common.Positionals;
const Options = common.Options;
const ArgumentTuple = common.ArgumentTuple;

/// verify all endpoints are unique and valid
pub fn endpoints(comptime endpoints_: []const type, comptime writer: type, comptime context: type) void {
    var seqs = ComptimeStringMapBuilder(endpoints_.len, []const u8){};
    inline for (endpoints_) |e| {
        const result = seqs.find(e.command_sequence);
        if (result.found) {
            const other = seqs.value_buffer[seqs.index_buffer[result.index]][1];
            @compileError("Endpoints '" ++ other ++
                "', and '" ++ @typeName(e) ++ "' have duplicate command_sequence '" ++ e.command_sequence ++ "'");
        } else {
            seqs.putFromResults(e.command_sequence, @typeName(e), result) catch {};
        }
        comptime endpoint(e, writer, context);
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
        if (!trait.isPtrTo(.@"struct")(writer)) {
            @compileError("expected pointer to struct, found " ++ @typeName(writer));
        }
        const WriterTy = std.meta.Child(writer);
        if (!trait.hasDecls(WriterTy, .{
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
pub fn endpoint(comptime endpoint_: type, comptime writer: type, comptime context: type) void {
    comptime {
        stringDeclaration(endpoint_, "command_sequence");
        stringDeclaration(endpoint_, "description_line");
        stringDeclaration(endpoint_, "description_full");
        arrayDeclaration(endpoint_, "options", Option);
        arrayDeclaration(endpoint_, "positionals", Positional);
        runFunction(endpoint_, writer, context);
        positionals(endpoint_);
        options(endpoint_);
        commandSequence(endpoint_, endpoint_.command_sequence);
    }
}

pub fn options(comptime endpoint_: type) void {
    if (endpoint_.options.len == 0) return;
    var names = ComptimeStringMapBuilder(endpoint_.options.len + 4, void){};
    var short_names = ComptimeStringMapBuilder(endpoint_.options.len + 3, void){};
    names.put("help", {}) catch {};
    names.put("h", {}) catch {};
    names.put("H", {}) catch {};
    names.put("?", {}) catch {};
    short_names.put("h", {}) catch {};
    short_names.put("H", {}) catch {};
    short_names.put("?", {}) catch {};
    inline for (endpoint_.options) |opt| {
        const result = names.find(opt.name);
        if (result.found)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'options' has duplicate name '--" ++ opt.name ++ "'")
        else {
            names.putFromResults(opt.name, {}, result) catch {};
        }
        if (opt.name_short) |short| {
            const short_str: []const u8 = &[_]u8{short};
            const result_short = short_names.find(short_str);
            if (result_short.found)
                @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                    "', field 'options' has duplicate short name '-" ++ short_str ++ "'")
            else {
                short_names.putFromResults(short_str, {}, result_short) catch {};
            }
        }
        arguments(endpoint_, opt.name, opt.arguments);
    }
}

pub fn arguments(comptime endpoint_: type, comptime opt_name: []const u8, comptime args: []const Argument) void {
    if (args.len == 0) return;
    var only_optionals: bool = false;
    inline for (args) |arg| {
        if (arg.isList() and args.len > 1)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'options', arguments for '--" ++ opt_name ++
                "' has list arg that is not the only arg");
        if (arg.isOptional()) {
            only_optionals = true;
        } else if (only_optionals)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'options', arguments for '--" ++ opt_name ++
                "' has optionals not orderd after non-optionals");
    }
}

pub fn positionals(comptime endpoint_: type) void {
    if (endpoint_.positionals.len == 0) return;
    var names = ComptimeStringMapBuilder(endpoint_.positionals.len, void){};
    var only_optionals: bool = false;
    inline for (endpoint_.positionals) |positional| {
        if (positional[0].len == 0)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'positionals' has an element with an empty name");
        if (positional[1].isList() and endpoint_.positionals.len > 1)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'positionals', list argument '" ++ positional[0] ++ "' must be the the only member");
        if (positional[1].isOptional()) {
            only_optionals = true;
        } else if (only_optionals)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'positionals', optional argument must appear after all non-optional arguments");
        const result = names.find(positional[0]);
        if (result.found)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "', field 'positionals' has duplicate name '" ++ positional[0] ++ "'")
        else {
            names.putFromResults(positional[0], {}, result) catch {};
        }
    }
}

pub fn commandSequence(comptime endpoint_: type, comptime command_sequence: []const u8) void {
    if (command_sequence.len == 0) return;
    if (command_sequence[0] == ' ')
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "', field 'command_sequence', value must not begin with a space");
    if (command_sequence[command_sequence.len - 1] == ' ')
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "', field 'command_sequence', value must not end with a space");
    if (std.mem.eql(u8, command_sequence, "help"))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "', field 'command_sequence' cannont equal 'help', help is a built in command");
    var prev_was_space: bool = false;
    for (command_sequence) |char| {
        commandSequenceChar(endpoint_, char);
        if (char == ' ') {
            if (prev_was_space)
                @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                    "', field 'command_sequence' commands must be delimited by exactly one space, no more")
            else
                prev_was_space = true;
        } else prev_was_space = false;
    }
}

pub fn commandSequenceChar(comptime endpoint_: type, comptime char: u8) void {
    if (!(char == ' ' or
        char == '-' or
        char == '_' or
        std.ascii.isAlphanumeric(char)))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' field 'command_sequence' has invalid char '" ++ &[_]u8{char} ++ "'");
}

/// verify endpoint's run function has the correct signiture
/// `fn(writer,Positionals,Options) anytype!void`
pub fn runFunction(comptime endpoint_: type, comptime writer: type, comptime context: type) void {
    if (!@hasDecl(endpoint_, "run"))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' missing public declaration 'run', should be " ++
            "'fn(std.mem.Allocator,*Writer,parsley.Positionals(positionals),parsley.Options(options))anyerror!void'")
    else if (trait.hasFn("run")(endpoint_)) {
        const info = @typeInfo(@TypeOf(endpoint_.run));
        if (info.@"fn".return_type != anyerror!void)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++
                "' declaration 'run' expected return value of 'anyerror!void' found '" ++ @typeName(info.Fn.return_type orelse noreturn) ++ "'");
        if (info.@"fn".params.len != 5)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected five parameters, " ++
                "fn(*Context,Allocator,*Writer,Positionals,Options)anyerror!void");
        if (info.@"fn".params[0].type != *context)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected first parameter" ++
                " of '" ++ @typeName(*context) ++ "'" ++ " found: " ++ @typeName(info.Fn.params[0].type orelse void));
        if (info.@"fn".params[1].type != std.mem.Allocator)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected second parameter" ++
                " of '" ++ @typeName(std.mem.Allocator) ++ "'" ++ " found: " ++ @typeName(info.Fn.params[0].type orelse void));
        if (info.@"fn".params[2].type != *writer)
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected third parameter" ++
                " of '" ++ @typeName(*writer) ++ "'" ++ " found: " ++ @typeName(info.Fn.params[1].type orelse void));
        if (info.@"fn".params[3].type != Positionals(endpoint_))
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected fourth parameter" ++
                " of 'parsley.Positionals(positionals)'" ++ " found: " ++ @typeName(info.Fn.params[2].type orelse void));
        if (info.@"fn".params[4].type != Options(endpoint_))
            @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' declaration 'run' expected fith parameter" ++
                " of 'parsley.Options(options)'" ++ " found: " ++ @typeName(info.Fn.params[3].type orelse void));
    } else @compileError("Endpoint '" ++ @typeName(endpoint_) ++
        ", expected 'run', to be function 'fn(std.mem.Allocator,*Writer,parsley.Positionals(positionals),parsley.Options(options))anyerror!void'");
}

/// emmits a compile error if the endpoint type does not contain a string declaration
/// with the given name
pub fn stringDeclaration(comptime endpoint_: type, comptime name: []const u8) void {
    const string_slice: []const u8 = "";
    if (!trait.is(.@"struct")(endpoint_))
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
    if (!trait.is(.@"struct")(endpoint_))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint_, name))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' missing public declaration '" ++ name ++ ": []const " ++ @typeName(child_type) ++ "'")
    else if (!trait.isPtrTo(.array)(@TypeOf(@field(endpoint_, name))))
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' incorrect type; expected '[]const " ++ @typeName(child_type) ++
            "' but found '" ++ @typeName(@TypeOf(@field(endpoint_, name))))
    else if (std.meta.Child(std.meta.Child(@TypeOf(@field(endpoint_, name)))) != child_type)
        @compileError("Endpoint '" ++ @typeName(endpoint_) ++
            "' incorrect type; expected '[]const " ++ @typeName(child_type) ++
            "' but found '" ++ @typeName(@TypeOf(@field(endpoint_, name))));
}
