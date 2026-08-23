pub const model = @import("model.zig");

const ids = @import("ids.zig");
pub const V7 = ids.V7;
pub const Uuid = ids.Uuid;
pub const ReplicaId = ids.ReplicaId;

const clock = @import("clock.zig");
pub const Clock = clock.Clock;
pub const Ts = clock.Ts;

test {
    _ = @import("ids.zig");
    _ = @import("clock.zig");
}
