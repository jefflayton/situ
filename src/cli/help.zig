const std = @import("std");

const Context = @import("Context.zig");
const cmd = @import("cmd/root.zig");

pub fn print(context: *Context, command: ?cmd.Command) void {
    var buf: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(context.io, &buf);
    var w = &stdout.interface;

    if (command) |c| {
        switch (c) {
            inline else => |tag| renderCommand(w, tag),
        }
    } else {
        renderRoot(w);
    }

    w.print("\n", .{}) catch {};
    w.flush() catch {};
}

pub fn renderRoot(w: *std.Io.Writer) void {
    w.print(
        \\Situ - Your notes, in place.
    , .{}) catch {};
}

fn renderCommand(w: *std.Io.Writer, c: cmd.Command) void {
    switch (c) {
        inline else => |tag| {
            const mod = @field(cmd.mods, @tagName(tag));
            w.print(
                \\{s}
            , .{mod.about}) catch {};
        },
    }
}
