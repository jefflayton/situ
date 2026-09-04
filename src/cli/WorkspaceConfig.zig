const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const core = @import("core");
const serde = @import("serde");
const toml = serde.toml;

const paths = @import("paths.zig");

const BUF_SIZE = 128;

pub const Data = struct {
    project_id: core.Uuid,
    workspace_id: core.Uuid,
};

arena: Arena,
dir: Io.Dir,
data: Data,

const WorkspaceConfig = @This();

pub fn deinit(self: *WorkspaceConfig) void {
    self.arena.deinit();
}

/// Reads the situ.toml located at `dir` into `data`
pub fn read(io: Io, gpa: Allocator, dir: Io.Dir) !?WorkspaceConfig {
    const file: ?Io.File = dir.openFile(io, "situ.toml", .{}) catch |err| switch (err) {
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

/// Writes to a situ.toml file
pub fn write(self: *WorkspaceConfig, io: Io) !void {
    var atomic = try self.dir.createFileAtomic(io, "situ.toml", .{ .replace = true });
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

    const p: core.Uuid = .{ .bytes = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 } };
    const w: core.Uuid = .{ .bytes = .{ 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32 } };
    var cfg: WorkspaceConfig = .{
        .arena = .init(gpa),
        .dir = tmp.dir,
        .data = .{
            .project_id = p,
            .workspace_id = w,
        },
    };
    defer cfg.deinit();
    try cfg.write(io);

    var got = (try WorkspaceConfig.read(io, gpa, tmp.dir)).?;
    defer got.deinit();

    try std.testing.expectEqualSlices(u8, &p.bytes, &got.data.project_id.bytes);
    try std.testing.expectEqualSlices(u8, &w.bytes, &got.data.workspace_id.bytes);
}
