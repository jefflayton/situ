const Uuid = @import("ids.zig").Uuid;
const core = @import("root.zig");

pub const Meta = struct {
    id: i2,
    replica_id: u64,
    last_hlc: [21]u8,
};

pub const Project = struct {
    id: Uuid,
    name: []const u8,
    created_ts: u64,
    updated_hlc: [21]u8,
};

pub const NewProject = struct {
    name: []const u8,
};

pub const Note = struct {
    id: Uuid,
    filepath: []const u8,
    project_id: Uuid,
    repo_id: ?Uuid,
    content: []const u8,
    version: i32,
    created_ts: u64,
    updated_hlc: [21]u8,
    deleted_ts: ?u64,
};
