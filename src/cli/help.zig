const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const Context = @import("Context.zig");
const cmd = @import("cmd/root.zig");

pub fn print(ctx: *Context, command: ?cmd.Command) !void {
    if (command) |c| {
        commandHelp(ctx.gpa, ctx.stdout, c) catch |err| {
            ctx.diag.set("stdout", "", "commandHelp", err);
            return err;
        };
    } else {
        rootHelp(ctx.gpa, ctx.stdout) catch |err| {
            ctx.diag.set("stdout", "", "rootHelp", err);
            return err;
        };
    }
}

fn rootHelp(gpa: Allocator, w: *Writer) !void {
    const cmds = try listCommands(gpa);
    defer gpa.free(cmds);

    const flags = try listFlags(cmd.Root, gpa);
    defer gpa.free(flags);

    try w.print(
        \\{s}
        \\
        \\Usage: {s}
        \\
        \\Commands:
        \\{s}
        \\
        \\Options:
        \\{s}
        \\
    , .{
        cmd.Root.about,
        cmd.Root.usage,
        cmds,
        flags,
    });

    try w.flush();
}

fn commandHelp(gpa: Allocator, w: *Writer, c: cmd.Command) !void {
    switch (c) {
        inline else => |tag| {
            const mod = @field(cmd.mods, @tagName(tag));
            const flags = try listFlags(mod.Opts, gpa);
            defer gpa.free(flags);

            try w.print(
                \\{s}
                \\
                \\Usage: {s} {s}
                \\
                \\Options:
                \\{s}
                \\
            , .{
                mod.Opts.about,
                @tagName(tag),
                mod.Opts.usage,
                flags,
            });
        },
    }
    try w.flush();
}

fn listCommands(gpa: Allocator) ![]u8 {
    const fields = @typeInfo(@TypeOf(cmd.mods)).@"struct".fields;
    var commands: [fields.len][]u8 = undefined;
    inline for (fields, 0..) |f, i| {
        const mod = @field(cmd.mods, f.name);
        const buf = try std.fmt.allocPrint(
            gpa,
            "    {s}        {s}",
            .{ f.name, mod.Opts.about },
        );
        commands[i] = buf;
    }
    defer inline for (commands) |c| gpa.free(c);
    return try std.mem.join(gpa, "\n", &commands);
}

fn listFlags(comptime T: type, gpa: Allocator) ![]u8 {
    cmd.assertOpts(T);

    const fields = @typeInfo(T).@"struct".fields;
    var flags: [fields.len][]u8 = undefined;
    inline for (fields, 0..) |f, i| {
        const about = @field(T.flags, f.name).about;
        const short: []const u8 =
            if (cmd.shortOf(T, f.name)) |s|
                &.{ '-', s, ',', ' ' }
            else
                "";

        const buf = try std.fmt.allocPrint(
            gpa,
            "    {s}--{s}        {s}",
            .{ short, f.name, about },
        );
        flags[i] = buf;
    }
    defer inline for (flags) |f| gpa.free(f);
    return try std.mem.join(gpa, "\n", &flags);
}

pub fn usage(ctx: *Context, command: ?cmd.Command) !void {
    if (command) |c| {
        commandUsage(ctx.stderr, c) catch |err| {
            ctx.diag.set("stderr", "", "commandUsage", err);
            return err;
        };
    } else {
        rootUsage(ctx.stderr) catch |err| {
            ctx.diag.set("stderr", "", "rootUsage", err);
            return err;
        };
    }
}

fn commandUsage(w: *Writer, c: cmd.Command) !void {
    switch (c) {
        inline else => |tag| {
            const mod = @field(cmd.mods, @tagName(tag));
            try w.print(
                "Usage: situ {s} {s}\n",
                .{ @tagName(tag), mod.Opts.usage },
            );
        },
    }
    try w.flush();
}

fn rootUsage(w: *Writer) !void {
    try w.print("Usage: situ {s}\n", .{cmd.Root.usage});
    try w.flush();
}
