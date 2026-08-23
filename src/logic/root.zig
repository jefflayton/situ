const std = @import("std");
const core = @import("core");
const store = @import("store");

pub const projects = @import("projects.zig");

pub const Ctx = struct {
    replica: core.ReplicaId,
    ids: *core.V7,
    io: std.Io,
};
