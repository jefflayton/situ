const std = @import("std");
const testing = std.testing;

const core = @import("core");
const sqlite = @import("sqlite");

/// Wraps core.ids.Uuid to provide binding functions for sqlite
pub const UuidCol = struct {
    inner: core.Uuid,

    /// Required declaration. Used by sqlite.
    pub const BaseType = sqlite.Blob;

    /// Used by sqlite to bind Uuid to Blob type
    pub fn bindField(self: UuidCol, alloc: std.mem.Allocator) !BaseType {
        const buf = try alloc.dupe(u8, &self.inner.bytes);
        return .{ .data = buf };
    }

    /// Used by sqlite to read the Blob type into UuidCol
    pub fn readField(_: std.mem.Allocator, value: BaseType) !UuidCol {
        if (value.data.len != 16) return error.InvalidUuid;
        var u: core.Uuid = .{ .bytes = undefined };
        @memcpy(&u.bytes, value.data);
        return .{ .inner = u };
    }
};

/// Wraps core.ids.ReplicaId to provide binding functions for sqlite
pub const ReplicaIdCol = struct {
    inner: core.ReplicaId,

    /// Required declaration. Used by sqlite.
    pub const BaseType = i64;

    /// Used by sqlite to bind retrieve value from ReplicaId
    pub fn bindField(self: ReplicaIdCol, _: std.mem.Allocator) !BaseType {
        return @bitCast(self.inner.value);
    }

    /// Used by sqlite to read u64 into a ReplicaId
    pub fn readField(_: std.mem.Allocator, value: BaseType) !ReplicaIdCol {
        return .{ .inner = .{ .value = @bitCast(value) } };
    }
};

/// Wraps core.clock.Ts to provide binding functions for sqlite
pub const TsCol = struct {
    inner: core.Ts,

    /// Required declaration. Used by sqlite.
    pub const BaseType = [21]u8;

    /// Used by sqlite to bind Ts to [21]u8
    pub fn bindField(self: TsCol, _: std.mem.Allocator) !BaseType {
        return self.inner.toString();
    }

    /// Used by sqlite to read []const u8 into Ts
    pub fn readField(_: std.mem.Allocator, value: BaseType) !TsCol {
        return .{ .inner = try core.Ts.parse(&value) };
    }
};

/// A variation of core.model.Meta that uses sqlite compatible structs
pub const MetaRow = struct {
    id: i2,
    project_name: []const u8,
    project_id: UuidCol,
    replica_id: ReplicaIdCol,
    last_hlc: TsCol,

    pub fn fromMeta(m: core.model.Meta) MetaRow {
        return .{
            .id = m.id,
            .project_name = m.project_name,
            .project_id = .{ .inner = m.project_id },
            .replica_id = .{ .inner = m.replica_id },
            .last_hlc = .{ .inner = m.last_hlc },
        };
    }

    pub fn toMeta(self: MetaRow) core.model.Meta {
        return .{
            .id = self.id,
            .project_name = self.project_name,
            .project_id = self.project_id.inner,
            .replica_id = self.replica_id.inner,
            .last_hlc = self.last_hlc.inner,
        };
    }
};

test "UuidCol roundtrips through bind/read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const u: core.Uuid = .{ .bytes = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 } };
    const encoded = try (UuidCol{ .inner = u }).bindField(arena.allocator());

    const decoded = try UuidCol.readField(arena.allocator(), encoded);
    try testing.expectEqual(u, decoded.inner);
}

test "ReplicaIdCol roundtrips through bind/read" {
    const r: core.ReplicaId = .{ .value = 0xDEADBEEF };
    const encoded = try (ReplicaIdCol{ .inner = r }).bindField(testing.allocator);
    const decoded = try ReplicaIdCol.readField(testing.allocator, encoded);
    try testing.expectEqual(r, decoded.inner);
}

test "TsCol roundtrips through bind/read" {
    const ts: core.Ts = .{ .wall = 1_700_000_000_000, .counter = 7 };
    const encoded = try (TsCol{ .inner = ts }).bindField(testing.allocator);
    const decoded = try TsCol.readField(testing.allocator, encoded);
    try testing.expectEqual(ts, decoded.inner);
}

test "MetaRow roundtrips Meta" {
    const m: core.model.Meta = .{
        .id = 1,
        .project_name = "Test",
        .project_id = .{ .bytes = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 } },
        .replica_id = .{ .value = 0xDEADBEEF },
        .last_hlc = .{ .wall = 1_700_000_000_000, .counter = 7 },
    };
    try testing.expectEqual(m, MetaRow.fromMeta(m).toMeta());
}
