const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ.Map;
const builtin = @import("builtin");

const core = @import("core");

pub const PathError = error{NoHomeDirectory};

/// Resolves a path between the XDG and $HOME variables.
/// Precedence Order:
///   - $XDG_*
///   - $HOME
fn xdgPath(gpa: Allocator, xdg: ?[]const u8, home: ?[]const u8, default_tail: []const []const u8, rest: []const []const u8) ![:0]u8 {
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
pub fn projectDb(gpa: Allocator, environ: *Environ, id: core.Uuid) ![:0]u8 {
    const home = environ.get("HOME");
    const xdg = environ.get("XDG_DATA_HOME");

    const h = &id.hex();
    return try xdgPath(gpa, xdg, home, &.{ ".local", "share" }, &.{ "situ", "projects", h, "store.db" });
}

/// Finds the situ/config.toml file
/// Precedence Order:
///   - $XDG_CONFIG_HOME/situ/config.toml
///   - $HOME/.config/situ/config.toml
pub fn configToml(gpa: Allocator, environ: *Environ) ![:0]u8 {
    const home = environ.get("HOME");
    const xdg = environ.get("XDG_CONFIG_HOME");

    return try xdgPath(gpa, xdg, home, &.{".config"}, &.{ "situ", "config.toml" });
}

/// Information on the nearest situ.toml
pub const Found = struct {
    dir: Io.Dir,
    path: [:0]u8,
    /// situ.toml could be a symlink in a secondary checkout
    linked: bool,

    pub fn deinit(self: *Found, io: Io, gpa: Allocator) void {
        self.dir.close(io);
        gpa.free(self.path);
    }
};

const DEPTH_CAP = 64;

/// Finds the nearest situ.toml, checking the `start` dir and walking up through its ancestors.
pub fn findWorkspaceRoot(io: Io, gpa: Allocator, start: Io.Dir) !?Found {
    var dir = try start.openDir(io, ".", .{});
    errdefer dir.close(io);

    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        if (dir.statFile(io, "situ.toml", .{ .follow_symlinks = false })) |st| {
            return .{
                .dir = dir,
                .path = try dir.realPathFileAlloc(io, ".", gpa),
                .linked = st.kind == .sym_link,
            };
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return e,
        }

        var parent = try dir.openDir(io, "..", .{});
        if (try sameDir(io, dir, parent)) {
            parent.close(io);
            break;
        }
        dir.close(io);
        dir = parent;
    }

    dir.close(io);
    return null;
}

/// Check if two directories are the same by comparing their `inode` stat.
fn sameDir(io: Io, a: Io.Dir, b: Io.Dir) !bool {
    const sa = try a.stat(io);
    const sb = try b.stat(io);
    return sa.inode == sb.inode;
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
    var environ_map = try environ.createMap(gpa);
    defer environ_map.deinit();

    const uuid: core.Uuid = .{ .bytes = .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } };

    const path = try projectDb(gpa, &environ_map, uuid);
    defer gpa.free(path);

    try std.testing.expectEqualStrings("/tmp/x/situ/projects/01010101010101010101010101010101/store.db", path);
}

test "configToml" {
    const gpa = std.testing.allocator;

    const vars = [_:null]?[*:0]const u8{"HOME=/tmp/h"};
    const block: std.process.Environ.PosixBlock = .{ .slice = &vars };
    const environ: std.process.Environ = .{ .block = block };
    var environ_map = try environ.createMap(gpa);
    defer environ_map.deinit();

    const path = try configToml(gpa, &environ_map);
    defer gpa.free(path);

    try std.testing.expectEqualStrings("/tmp/h/.config/situ/config.toml", path);
}
