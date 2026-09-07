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

    var global: cmd.Global = .{};
    while (args.next()) |a| {
        if (a.len == 0) continue;
        if (std.mem.eql(u8, a, "--")) break;

        // TODO: Read struct, not manual check
        if (std.mem.eql(u8, a, "--version")) {
            return .version;
        }
        // TODO: Read struct, not manual check
        if (std.mem.eql(u8, a, "--help")) {
            global.help = true;
            continue;
        }

        if (std.meta.stringToEnum(cmd.Command, a)) |c| {
            switch (c) {
                inline else => |tag| {
                    const T = @FieldType(@FieldType(cmd.Parsed, "command"), @tagName(tag));
                    const opts = try parseInto(T, args, &global);
                    if (global.help) return .{ .help = c };
                    return .{ .command = @unionInit(
                        @FieldType(cmd.Parsed, "command"),
                        @tagName(tag),
                        opts,
                    ) };
                },
            }
        }

        // Fix: better unknown arg handling
        if (!global.help) return error.UnknownArg;
    }

    return .{ .help = null };
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

/// Finds and returns the short form of a field, if one exists
fn shortOf(comptime T: type, comptime field: []const u8) ?u8 {
    if (!@hasDecl(T, "short")) return null;
    if (!@hasField(@TypeOf(T.short), field)) return null;
    return @field(T.short, field);
}

/// Attempts to find the argument in target by its short form and write to it
fn tryShort(comptime T: type, target: *T, ch: u8, is_last: bool, args: *ArgsIter) Error!bool {
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (shortOf(T, f.name) == ch) {
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
            .expect = .{ .want = .version },
        },
        .{
            .args = .{ .vector = &.{ "dud", "--help" } },
            .expect = .{ .want = .{ .help = null } },
        },
        .{
            .args = .{ .vector = &.{"dud"} },
            .expect = .{ .want = .{ .help = null } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "--", "init" } },
            .expect = .{ .want = .{ .help = null } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "init" } },
            .expect = .{ .want = .{ .command = .{ .init = .{} } } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "--help", "init" } },
            .expect = .{ .want = .{ .help = cmd.Command.init } },
        },
        .{
            .args = .{ .vector = &.{ "dud", "init", "--help" } },
            .expect = .{ .want = .{ .help = cmd.Command.init } },
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
        .{
            .args = .{ .vector = &.{"--help"} },
            .expect = .{ .want = .{ .opts = .{}, .global = .{ .help = true } } },
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
        optional: ?[]const u8 = null,
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
            .name = "optional",
            .expect = .{ .want = .{ .ok = true, .target = .{ .optional = "val" } } },
        },
        .{
            .args = .{ .vector = &.{} },
            .name = "optional",
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
        optional: ?[]const u8 = null,
        pub const short = .{ .flag = 'f', .optional = 'o' };
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
            .expect = .{ .want = .{ .ok = true, .target = .{ .optional = "val" } } },
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
