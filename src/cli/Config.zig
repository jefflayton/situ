const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const core = @import("core");
const toml = @import("serde").toml;

const paths = @import("paths.zig");

const BUF_SIZE = 1024;

pub const Checkout = struct {
    path: []const u8,
    project_id: core.Uuid,
    workspace_id: core.Uuid,
};

pub const Data = struct {
    version: u32 = 1,
    checkouts: []const Checkout = &.{},
};

arena: Arena,
dir: Io.Dir,
data: Data,

const Config = @This();

pub fn deinit(self: *Config) void {
    self.arena.deinit();
}

// Reads and deserializes the global config.toml
pub fn read(io: Io, gpa: Allocator, dir: Io.Dir) !?Config {
    const file: ?Io.File = dir.openFile(io, "config.toml", .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => |e| return e,
    };

    if (file) |f| {
        defer f.close(io);

        var arena: Arena = .init(gpa);
        errdefer arena.deinit();

        var buf: [BUF_SIZE]u8 = undefined;
        var r = f.reader(io, &buf);
        const data = try toml.fromReader(Data, arena.allocator(), &r.interface);

        return .{ .arena = arena, .dir = dir, .data = data };
    }
    return null;
}

/// Writes to the global config.toml
pub fn write(self: *Config, io: Io) !void {
    var atomic = try self.dir.createFileAtomic(io, "config.toml", .{ .replace = true });
    defer atomic.deinit(io);

    var buf: [BUF_SIZE]u8 = undefined;
    var w = atomic.file.writer(io, &buf);
    try toml.toWriter(self.arena.allocator(), &w.interface, self.data);
    try w.flush();

    try atomic.file.sync(io);
    try atomic.replace(io);
}

test {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var cfg: Config = .{
        .arena = .init(gpa),
        .dir = tmp.dir,
        .data = .{
            .version = 1,
        },
    };
    defer cfg.deinit();
    try cfg.write(io);

    var got = (try Config.read(io, gpa, tmp.dir)).?;
    defer got.deinit();

    try std.testing.expectEqual(1, got.data.version);
}
