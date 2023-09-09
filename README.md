# parsley

A command line parser written in zig.


```zig
const std = @import("std");
const parsley = @import("parsley");

pub fn main() !void {
    var writer = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    try parsley.run(allocator, &writer, &.{Endpoint1}, .{});
}

/// runnable commands are defined by structs called endpoints
const Endpoint1 = struct {
    pub const command_sequence = "command subcommand";
    pub const description_line = "Single line description";
    pub const description_full = description_line ++ "\nExtra info";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};

    pub fn run(
        writer: *parsley.Writer,
        poss: parsley.Positionals(positionals),
        pots: parsley.Options(options),
    ) anyerror!void {
        // do it
    }
};

/// provide descriptions for non runnable commands
const command_descriptions = &[_]parsley.CommandDescription{
    .{
        .command_sequence = "",
        .line = "not used",
        .full = "empty string is the root command, ie no command\n" ++
            "yes, you may define an endpoint for the root command, " ++
            "just set `command_sequence` to an empty string",
    },
    .{
        .command_sequence = "command",
        .line = "A simple command with one sub command",
        .full = "A simple command with one sub command\n" ++
            "parsley knows this command exists because it " ++
            "appears in the `command_sequence` for `Endpoint1`",
    },
};
```

## License
---
> MIT License
>
> Copyright (c) 2023 Patrick Torgerson
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.
