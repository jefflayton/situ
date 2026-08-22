const Uuid = @import("ids.zig").Uuid;

pub const Project = struct {
    id: Uuid,
    name: []const u8,
    created_ts: i64,
    updated_ts: i64,
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
    created_ts: i64,
    updated_ts: i64,
    deleted_ts: ?i64,
};
