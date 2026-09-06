const core = @import("root.zig");
const Uuid = core.Uuid;
const ReplicaId = core.ReplicaId;
const Ts = core.Ts;

pub const Meta = struct {
    id: i2,
    project_name: []const u8,
    project_id: Uuid,
    replica_id: ReplicaId,
    last_hlc: Ts,
};

pub const Workspace = struct {
    id: Uuid,
    name: []const u8,
    created_ts: u64,
    updated_hlc: Ts,
};

pub const Note = struct {
    id: Uuid,
    filepath: []const u8,
    project_id: Uuid,
    repo_id: ?Uuid,
    content: []const u8,
    version: i32,
    created_ts: u64,
    updated_hlc: Ts,
    deleted_ts: ?u64,
};
