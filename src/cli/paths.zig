const std = @import("std");
const builtin = @import("builtin");

const core = @import("core");

pub const PathError = error{NoHomeDirectory};

/// Resolves a path between the XDG and $HOME variables.
/// Precedence Order:
///   - $XDG_*
///   - $HOME
fn xdgPath(gpa: std.mem.Allocator, xdg: ?[]const u8, home: ?[]const u8, default_tail: []const []const u8, rest: []const []const u8) ![:0]u8 {
    var buf: [4][]const u8 = undefined;
    const base: []const []const u8 = if (xdg) |x| blk: {
        buf[0] = x;
        break :blk buf[0..1];
    } else if (home) |h| blk: {
        buf[0] = h;
        @memcpy(buf[1..][0..default_tail.len], default_tail);
        break :blk buf[0 .. 1 + default_tail.len];
    } else {
        return PathError.NoHomeDirectory;
    };

    const path = try std.mem.concat(gpa, []const u8, &.{ base, rest });
    defer gpa.free(path);

    return try std.fs.path.joinZ(gpa, path);
}

/// Finds the situ/project/{uuid}/store.db file
/// Precedence Order:
///   - $XDG_DATA_HOME/situ/project/{uuid}/store.db
///   - $HOME/.local/share/situ/project/{uuid}/store.db
pub fn projectDb(gpa: std.mem.Allocator, environ: std.process.Environ, id: core.Uuid) ![:0]u8 {
    const home = environ.getAlloc(gpa, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => |e| return e,
    };
    defer if (home) |h| gpa.free(h);

    const xdg = environ.getAlloc(gpa, "XDG_DATA_HOME") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => |e| return e,
    };
    defer if (xdg) |x| gpa.free(x);

    const h = &id.hex();
    return try xdgPath(gpa, xdg, home, &.{ ".local", "share" }, &.{ "situ", "projects", h, "store.db" });
}

/// Finds the situ/config.toml file
/// Precedence Order:
///   - $XDG_CONFIG_HOME/situ/config.toml
///   - $HOME/.config/situ/config.toml
pub fn configToml(gpa: std.mem.Allocator, environ: std.process.Environ) ![:0]u8 {
    const home = environ.getAlloc(gpa, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => |e| return e,
    };
    defer if (home) |h| gpa.free(h);

    const xdg = environ.getAlloc(gpa, "XDG_CONFIG_HOME") catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => |e| return e,
    };
    defer if (xdg) |x| gpa.free(x);

    return try xdgPath(gpa, xdg, home, &.{".config"}, &.{ "situ", "config.toml" });
}

test "xdgPath" {
    const gpa = std.testing.allocator;
    const Case = struct {
        xdg: ?[]const u8,
        home: ?[]const u8,
        default_tail: []const []const u8 = &.{},
        rest: []const []const u8 = &.{"situ"},
        want: ?[]const u8 = null,
        err: ?PathError = null,
    };

    const cases = [_]Case{
        .{ .xdg = "/x", .home = "/h", .want = "/x/situ" },
        .{
            .xdg = null,
            .home = "/h",
            .default_tail = &.{ ".local", "share" },
            .want = "/h/.local/share/situ",
        },
        .{ .xdg = "/x", .home = null, .want = "/x/situ" },
        .{ .xdg = null, .home = null, .err = PathError.NoHomeDirectory },
    };

    for (cases) |c| {
        const path = xdgPath(gpa, c.xdg, c.home, c.default_tail, c.rest);

        if (c.want) |w| {
            const p = try path;
            defer gpa.free(p);

            try std.testing.expectEqualStrings(w, p);
        } else if (c.err) |e| {
            try std.testing.expectError(e, path);
        } else {
            try std.testing.expect(false);
        }
    }
}

test "projectDb" {
    const gpa = std.testing.allocator;

    const vars = [_:null]?[*:0]const u8{ "HOME=/tmp/h", "XDG_DATA_HOME=/tmp/x" };
    const block: std.process.Environ.PosixBlock = .{ .slice = &vars };
    const environ: std.process.Environ = .{ .block = block };

    const uuid: core.Uuid = .{ .bytes = .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } };

    const path = try projectDb(gpa, environ, uuid);
    defer gpa.free(path);

    try std.testing.expectEqualStrings("/tmp/x/situ/projects/01010101010101010101010101010101/store.db", path);
}

test "configToml" {
    const gpa = std.testing.allocator;

    const vars = [_:null]?[*:0]const u8{"HOME=/tmp/h"};
    const block: std.process.Environ.PosixBlock = .{ .slice = &vars };
    const environ: std.process.Environ = .{ .block = block };

    const path = try configToml(gpa, environ);
    defer gpa.free(path);

    try std.testing.expectEqualStrings("/tmp/h/.config/situ/config.toml", path);
}
