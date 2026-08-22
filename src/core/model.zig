pub const Note = struct {
    id: []const u8,
    filepath: []const u8,
    project_id: []const u8,
    repo_id: ?[]const u8,
    content: []const u8,
    version: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
};
