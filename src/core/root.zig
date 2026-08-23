pub const model = @import("model.zig");

const ids = @import("ids.zig");
pub const V7 = ids.V7;
pub const Uuid = ids.Uuid;
pub const ReplicaId = ids.ReplicaId;

test {
    _ = @import("ids.zig");
}
