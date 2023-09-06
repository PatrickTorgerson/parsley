# parsley

A command line parser written in zig.

## basic example

```zig
const std = @import("std");
const parsley = @import("parsley");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var buffered_writer = std.io.bufferedWriter(stdout_file);
    const writer = buffered_writer.writer();

    try parsley.parse(&writer, &.{CmdEncrypt}, .{});
}

// command endpoints are defined by structs
const CmdEncrypt = struct {
    pub const command_sequence = "encrypt";
    pub const description_line = "Encrypt text data";
    pub const description_full = description_line;
    pub const options = &[_]parsley.Option{
        .{
            .name = "file",
            .name_short = 'f',
            .description = "Encrypt contents of a file",
            .arguments: &.{.string},
        },
        .{
            .name = "out",
            .name_short = 'o',
            .description = "Write encrypted output to a file",
            .arguments: &.{.string},
        },
    };
    pub const positionals = &[_]parsley.Argument{};

    pub fn run(
        writer: *parsley.Writer,
        option_values: parsley.Options(options),
        positional_values: parsley.Positionals(positionals),
    ) void {
        // do it
    }
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
