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
    /// see below for possible values
    arguments: []const Argument,
};

/// enum of possible argument types
pub const Argument = enum {
    number,
    boolean,
    string,
    optional_number,
    optional_boolean,
    optional_string,
    number_list,
    boolean_list,
    string_list,
};

/// description information for a single command
pub const CommandDescription = struct {
    name: []const u8,
    line: []const u8,
    full: []const u8,
};

/// configuration options for the library
pub const Configuration = struct {
    max_commands: usize = 64,
    max_subcommands: usize = 16,
};

/// parse the commandline calling the specified endpoint
pub fn parse(comptime endpoints: []const type, comptime config: Configuration) !void {
    const data = comptime buildData(endpoints, config);
    _ = data;
}

/// a collection of std.ComptimeStringMap() containing
/// data for each command
const Data = struct {
    help_fns: type,
    parse_fns: type,
    line_descs: type,
    full_descs: type,
    subcommands: type,
};

/// build
fn buildData(comptime endpoints: []const type, comptime config: Configuration) Data {
    inline for (endpoints) |e| {
        verifyEndpoint(e);
    }
    _ = config;
    return .{
        .help_fns = void,
        .parse_fns = void,
        .line_descs = void,
        .full_descs = void,
        .subcommands = void,
    };
}

pub fn Positionals(comptime positionals: []const Argument) type {
    _ = positionals;
    return void;
}

pub fn Options(comptime options: []const Option) type {
    _ = options;
    return void;
}

/// ensure the given type meets the constraints
/// to be an endpoint struct, emmits a compile error otherwise
fn verifyEndpoint(comptime endpoint: type) void {
    if (@hasDecl(endpoint, "command_descriptions")) {
        verifyArrayDeclaration(endpoint, "command_descriptions", CommandDescription);

        if (!(@hasDecl(endpoint, "command_sequence") or
            @hasDecl(endpoint, "description_line") or
            @hasDecl(endpoint, "description_full") or
            @hasDecl(endpoint, "options") or
            @hasDecl(endpoint, "positionals") or
            @hasDecl(endpoint, "run")))
            return;
    }

    verifyStringDeclaration(endpoint, "command_sequence");
    verifyStringDeclaration(endpoint, "description_line");
    verifyStringDeclaration(endpoint, "description_full");
    verifyArrayDeclaration(endpoint, "options", Option);
    verifyArrayDeclaration(endpoint, "positionals", Argument);

    if (!@hasDecl(endpoint, "run"))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' missing public declaration 'run', should be 'null' or " ++
            "'fn(parsley.Positionals(positionals),parsley.Options(options))void'")
    else if (std.meta.trait.hasFn("run")(endpoint)) {
        const info = @typeInfo(@TypeOf(endpoint.run));
        if (info.Fn.return_type != void)
            @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected return value of 'void'");
        if (info.Fn.params.len != 2)
            @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected two parameters" ++
                "parsley.Positionals(positionals), and parsley.Options(options)");
        if (info.Fn.params[0].type != Positionals(endpoint.positionals))
            @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected first parameter" ++
                " of 'parsley.Positionals(positionals)'");
        if (info.Fn.params[1].type != Options(endpoint.options))
            @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' declaration 'run' expected second parameter" ++
                " of 'parsley.Options(options)'");
    } else if (@TypeOf(endpoint.run) != @TypeOf(null))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            " declaration 'run' expected 'null' or 'fn(parsley.Positionals(positionals),parsley.Options(options))void'");
}

/// emmits a compile error if the endpoint type does not contain a string declaration
/// with the given name
fn verifyStringDeclaration(comptime endpoint: type, comptime name: []const u8) void {
    const string_slice: []const u8 = "";
    if (!std.meta.trait.is(.Struct)(endpoint))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint, name))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' missing public declaration '" ++ name ++ ": []const u8'")
    else if (@TypeOf(@field(endpoint, name), string_slice) != []const u8)
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' declaration '" ++ name ++ "' incorrect type '" ++
            @typeName(@TypeOf(@field(endpoint, name))) ++ "', should be '[]const u8'");
}

/// emmits a compile error if the endpoint type does not contain a array declaration
/// with the given name
fn verifyArrayDeclaration(comptime endpoint: type, comptime name: []const u8, comptime child_type: type) void {
    const child_slice: []const child_type = &.{};
    if (!std.meta.trait.is(.Struct)(endpoint))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++ "' expected to be a struct type");
    if (!@hasDecl(endpoint, name))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' missing public declaration '" ++ name ++ ": []const " ++ @typeName(child_type) ++ "'")
    else if (@TypeOf(@field(endpoint, name), child_slice) != @TypeOf(child_slice))
        @compileError("Endpoint '" ++ @typeName(endpoint) ++
            "' declaration '" ++ name ++ "' incorrect type '" ++
            @typeName(@TypeOf(@field(endpoint, name))) ++ "', should be '[]const " ++
            @typeName(child_type) ++ "'");
}

test {}
