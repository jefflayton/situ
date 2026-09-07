const std = @import("std");
const ArrayList = std.array_list.Managed;
const Args = std.process.Args;
const ArgsIter = Args.Iterator;
const Allocator = std.mem.Allocator;
const StructField = std.builtin.Type.StructField;

const cmd = @import("cmd/root.zig");

const Error = error{ UnknownArg, MissingValue, InvalidBundle };

pub fn parse(args: *ArgsIter) Error!cmd.Parsed {
    _ = args.next() orelse return error.UnknownArg; // program name

    var root: cmd.Root = .{};
    var global: cmd.Global = .{};
    outer: while (args.next()) |a| {
        if (a.len == 0) continue;
        if (std.mem.eql(u8, a, "--")) break;
        if (root.help or root.version) return .{ .root = root };

        if (a.len > 2 and std.mem.startsWith(u8, a, "--")) {
            const name = a[2..];
            if (try tryLong(cmd.Root, &root, name, args)) continue :outer;
        } else if (a.len > 1 and std.mem.startsWith(u8, a, "-")) {
            for (a[1..], 0..) |ch, i| {
                const is_last = i == a.len - 2;

                if (try tryShort(cmd.Root, &root, ch, is_last, args)) continue :outer;
                return error.UnknownArg;
            }
            continue :outer;
        }

        if (std.meta.stringToEnum(cmd.Command, a)) |c| {
            switch (c) {
                inline else => |tag| {
                    const T = @FieldType(@FieldType(cmd.Parsed, "command"), @tagName(tag));
                    const opts = try parseInto(T, args, &global);
                    return .{ .command = @unionInit(
                        @FieldType(cmd.Parsed, "command"),
                        @tagName(tag),
                        opts,
                    ) };
                },
            }
        }

        return error.UnknownArg;
    }

    return .{ .root = root };
}

/// Writes to the argument in target
fn assign(comptime T: type, target: *T, field: StructField, args: *ArgsIter) Error!void {
    if (field.type == bool) {
        @field(target, field.name) = true;
    } else if (@typeInfo(field.type) == .optional) {
        @field(target, field.name) = args.next() orelse return error.MissingValue;
    } else @compileError(@typeName(T) ++ ": " ++ @typeName(field.type) ++ "not supported.");
}

/// Parses args "into" a Command's Opts
pub fn parseInto(comptime T: type, args: *ArgsIter, global: *cmd.Global) Error!T {
    var opts: T = .{};

    outer: while (args.next()) |a| {
        if (a.len == 0) continue;
        if (std.mem.eql(u8, a, "--")) break;

        // TODO: support short names
        if (a.len > 2 and std.mem.startsWith(u8, a, "--")) {
            const name = a[2..];

            if (try tryLong(cmd.Global, global, name, args)) continue :outer;
            if (try tryLong(T, &opts, name, args)) continue :outer;
        } else if (a.len > 1 and std.mem.startsWith(u8, a, "-")) {
            for (a[1..], 0..) |ch, i| {
                const is_last = i == a.len - 2;

                if (try tryShort(cmd.Global, global, ch, is_last, args)) continue :outer;
                if (try tryShort(T, &opts, ch, is_last, args)) continue :outer;
                return error.UnknownArg;
            }
            continue :outer;
        }

        return error.UnknownArg;
    }
    return opts;
}
/// Attempts to find the argument in target and write to it
fn tryLong(comptime T: type, target: *T, name: []const u8, args: *ArgsIter) Error!bool {
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (std.mem.eql(u8, name, f.name)) {
            try assign(T, target, f, args);
            return true;
        }
    }
    return false;
}

/// Attempts to find the argument in target by its short form and write to it
fn tryShort(comptime T: type, target: *T, ch: u8, is_last: bool, args: *ArgsIter) Error!bool {
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (cmd.shortOf(T, f.name) == ch) {
            if (@typeInfo(f.type) == .optional and !is_last) return error.InvalidBundle;
            try assign(T, target, f, args);
            return true;
        }
    }
    return false;
}

test "parse" {
    const Case = struct {
        args: Args,
        expect: union(enum) { want: cmd.Parsed, err: Error },
    };

    const cases = [_]Case{
        .{
            .args = .{ .vector = &.{} },
            .expect = .{ .err = error.UnknownArg },
        },
        .{
            .args = .{ .vector = &.{ "dud", "--version" } },
            .expect = .{ .want = .{ .root = .{ .version = true } } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "--help" } },
            .expect = .{ .want = .{ .root = .{ .help = true } } },
        },
        // .{
        //     .args = .{ .vector = &.{ "dud", "-h" } },
        //     .expect = .{ .want = .{ .root = .{ .help = true } } },
        // },
        .{
            .args = .{ .vector = &.{ "dud", "--help", "init" } },
            .expect = .{ .want = .{ .root = .{ .help = true } } },
        },
        .{
            .args = .{ .vector = &.{"dud"} },
            .expect = .{ .want = .{ .root = .{} } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "--", "init" } },
            .expect = .{ .want = .{ .root = .{} } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "init" } },
            .expect = .{ .want = .{ .command = .{ .init = .{} } } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "init", "--help" } },
            .expect = .{ .want = .{ .command = .{ .init = .{ .help = true } } } },
        },
    };

    for (cases) |c| {
        var iter = c.args.iterate();
        const res = parse(&iter);
        switch (c.expect) {
            .want => |w| {
                const opts = try res;
                try std.testing.expectEqualDeep(w, opts);
            },
            .err => |e| try std.testing.expectError(e, res),
        }
    }
}

test "parseInto" {
    const Opts = struct {
        flag: bool = false,
        option: ?[]const u8 = null,

        pub const flags = .{
            .flag = .{ .short = 'f' },
            .option = .{ .short = 'o' },
        };
    };

    const Case = struct {
        args: Args,
        expect: union(enum) {
            want: struct { opts: Opts, global: cmd.Global },
            err: Error,
        },
    };

    const cases = [_]Case{
        .{
            .args = .{ .vector = &.{"--flag"} },
            .expect = .{ .want = .{ .opts = .{ .flag = true }, .global = .{} } },
        },
        .{
            .args = .{ .vector = &.{ "--option", "val" } },
            .expect = .{ .want = .{ .opts = .{ .option = "val" }, .global = .{} } },
        },
        .{
            .args = .{ .vector = &.{"--option"} },
            .expect = .{ .err = error.MissingValue },
        },
        .{
            .args = .{ .vector = &.{ "--flag", "--option", "val" } },
            .expect = .{ .want = .{ .opts = .{ .flag = true, .option = "val" }, .global = .{} } },
        },
        .{
            .args = .{ .vector = &.{ "--", "--flag", "--option", "val" } },
            .expect = .{ .want = .{ .opts = .{}, .global = .{} } },
        },
    };

    for (cases) |c| {
        var iter = c.args.iterate();
        var global: cmd.Global = .{};
        const res = parseInto(Opts, &iter, &global);
        switch (c.expect) {
            .want => |w| {
                const opts = try res;
                try std.testing.expectEqualDeep(w.opts, opts);
                try std.testing.expectEqualDeep(w.global, global);
            },
            .err => |e| try std.testing.expectError(e, res),
        }
    }
}

test "tryLong" {
    const Opts = struct {
        flag: bool = false,
        option: ?[]const u8 = null,

        pub const flags = .{
            .flag = .{ .short = 'f' },
            .option = .{ .short = 'o' },
        };
    };

    const Case = struct {
        args: Args,
        name: []const u8,
        expect: union(enum) {
            want: struct { ok: bool, target: Opts },
            err: Error,
        },
    };

    const cases = [_]Case{
        .{
            .args = .{ .vector = &.{} },
            .name = "flag",
            .expect = .{ .want = .{ .ok = true, .target = .{ .flag = true } } },
        },
        .{
            .args = .{ .vector = &.{"val"} },
            .name = "option",
            .expect = .{ .want = .{ .ok = true, .target = .{ .option = "val" } } },
        },
        .{
            .args = .{ .vector = &.{} },
            .name = "option",
            .expect = .{ .err = error.MissingValue },
        },
        .{
            .args = .{ .vector = &.{} },
            .name = "dud",
            .expect = .{ .want = .{ .ok = false, .target = .{} } },
        },
    };

    for (cases) |c| {
        var iter = c.args.iterate();
        var opts: Opts = .{};
        const res = tryLong(Opts, &opts, c.name, &iter);
        switch (c.expect) {
            .want => |w| {
                const ok = try res;
                try std.testing.expectEqual(w.ok, ok);
                try std.testing.expectEqualDeep(w.target, opts);
            },
            .err => |e| try std.testing.expectError(e, res),
        }
    }
}

test "tryShort" {
    const Opts = struct {
        flag: bool = false,
        option: ?[]const u8 = null,
        pub const flags = .{
            .flag = .{ .short = 'f' },
            .option = .{ .short = 'o' },
        };
    };

    const Case = struct {
        args: Args,
        name: u8,
        is_last: bool = false,
        expect: union(enum) {
            want: struct { ok: bool, target: Opts },
            err: Error,
        },
    };

    const cases = [_]Case{
        .{
            .args = .{ .vector = &.{} },
            .name = 'f',
            .expect = .{ .want = .{ .ok = true, .target = .{ .flag = true } } },
        },
        .{
            .args = .{ .vector = &.{"val"} },
            .name = 'o',
            .is_last = true,
            .expect = .{ .want = .{ .ok = true, .target = .{ .option = "val" } } },
        },
        .{
            .args = .{ .vector = &.{"val"} },
            .name = 'o',
            .is_last = false,
            .expect = .{ .err = error.InvalidBundle },
        },
        .{
            .args = .{ .vector = &.{} },
            .name = 'o',
            .is_last = true,
            .expect = .{ .err = error.MissingValue },
        },
        .{
            .args = .{ .vector = &.{} },
            .name = 'o',
            .is_last = false,
            .expect = .{ .err = error.InvalidBundle },
        },
        .{
            .args = .{ .vector = &.{} },
            .name = 'x',
            .expect = .{ .want = .{ .ok = false, .target = .{} } },
        },
    };

    for (cases) |c| {
        var iter = c.args.iterate();
        var opts: Opts = .{};
        const res = tryShort(Opts, &opts, c.name, c.is_last, &iter);
        switch (c.expect) {
            .want => |w| {
                const ok = try res;
                try std.testing.expectEqual(w.ok, ok);
                try std.testing.expectEqualDeep(w.target, opts);
            },
            .err => |e| try std.testing.expectError(e, res),
        }
    }
}
