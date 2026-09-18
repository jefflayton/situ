const std = @import("std");
const Allocator = std.mem.Allocator;

const cmd = @import("cmd/root.zig");
const Context = @import("Context.zig");

/// Input loop to choose an index from a list of items.
pub fn choose(ctx: *Context, comptime T: type, items: []const T, label: []const u8) cmd.CommandError!?usize {
    try ctx.stdout.print("\nSelect {s} index:\n", .{label});
    try ctx.stdout.print("0 - New {s}\n", .{label});
    for (items, 1..) |it, i| {
        try ctx.stdout.print("{d} - {s}\n", .{ i, it });
    }
    try ctx.stdout.flush();

    var idx: ?usize = null;
    outer: while (true) {
        try ctx.stdout.print("\nSelect {s} (enter the index number): ", .{label});
        try ctx.stdout.flush();

        const res = ctx.stdin.takeDelimiter('\n') catch |err| {
            ctx.diag.set("stdin", "choose", "takeDelimiter", err);
            return error.Io;
        };
        if (res) |r| {
            const trimmed = std.mem.trim(u8, r, " \t\r");

            const i = std.fmt.parseInt(usize, trimmed, 10) catch |err| switch (err) {
                error.InvalidCharacter => {
                    try ctx.stderr.print("Invalid Character. Please try again\n", .{});
                    try ctx.stderr.flush();
                    continue :outer;
                },
                else => |e| {
                    ctx.diag.set("stdin", "choose", "fmt.parseInt", e);
                    return error.Io;
                },
            };
            if (i == 0) break;
            if (0 < i and i <= items.len) {
                idx = i - 1;
                break;
            }
            try ctx.stderr.print("Invalid index", .{});
            try ctx.stderr.flush();
        }
    }
    return idx;
}

/// Input loop to take a text input from the user
pub fn text(ctx: *Context, arena: Allocator, label: []const u8) ![]const u8 {
    return blk: while (true) {
        try ctx.stdout.print("Enter {s}: ", .{label});
        try ctx.stdout.flush();

        const res = ctx.stdin.takeDelimiter('\n') catch |err| {
            ctx.diag.set("stdin", "text", "takeDelimiter", err);
            return error.Io;
        };
        if (res) |r| if (r.len > 0) {
            const in: []const u8 = try arena.dupe(u8, r);
            break :blk in;
        };
    };
}

pub fn confirm(ctx: *Context, label: []const u8) !bool {
    return blk: while (true) {
        try ctx.stdout.print("{s} (Y/N): ", .{label});
        try ctx.stdout.flush();

        const res = ctx.stdin.takeDelimiter('\n') catch |err| {
            ctx.diag.set("stdin", "confirm", "takeDelimiter", err);
            return error.Io;
        };
        if (res) |r| if (r.len == 1) switch (r[0]) {
            'Y', 'y' => break :blk true,
            'N', 'n' => break :blk false,
            else => {},
        };
    };
}
