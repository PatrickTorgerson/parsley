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

    try parsley.executeCommandLine(void, undefined, allocator, &writer, &.{Endpoint1}, .{.command_descriptions = command_descriptions});
}

/// runnable commands are defined by structs called endpoints
const Endpoint1 = struct {
    pub const command_sequence = "command subcommand";
    pub const description_line = "Single line description";
    pub const description_full = description_line ++ "\nExtra info";
    pub const options = &[_]parsley.Option{};
    pub const positionals = &[_]parsley.Positional{};

    pub fn run(
        context: *void,
        allocator: std.mem.Allocator,
        writer: *parsley.Writer,
        poss: parsley.Positionals(@This()),
        opts: parsley.Options(@This()),
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

see /examples

## usage

1. Add `parsley` as a dependency in your `build.zig.zon`.

    <details>

    <summary><code>build.zig.zon</code> example</summary>

    ```zig
    .{
        .name = "<name_of_your_package>",
        .version = "<version_of_your_package>",
        .dependencies = .{
            .parsley = .{
                .url = "https://github.com/PatrickTorgerson/parsley/archive/<git_tag_or_commit_hash>.tar.gz",
                .hash = "<package_hash>",
            },
        },
    }
    ```

    Set `<package_hash>` to `12200000000000000000000000000000000000000000000000000000000000000000`, and Zig will provide the correct found value in an error message.

    </details>

2. Add `parsley` as a module in your `build.zig`.

    <details>

    <summary><code>build.zig</code> example</summary>

    ```zig
    const parsley = b.lazyDependency("parsley", .{
        .optimize = optimize,
        .target = target,
    }).module("parsley");
    //...
    exe.root_module.addImport("parsley", parsley);
    ```

    </details>

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
