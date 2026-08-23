const std = @import("std");
const core = @import("core");
const store = @import("store");

pub const meta = @import("meta.zig");
pub const projects = @import("projects.zig");

pub const Ctx = struct {
    io: std.Io,
    replica_id: core.ReplicaId,
    ids: *core.V7,
    clock: *core.Clock,
};

pub fn withTxn(
    s: anytype,
    ctx: *Ctx,
    args: anytype,
    comptime f: anytype,
) @TypeOf(f(
    @as(*TxnOf(@TypeOf(s)), undefined),
    ctx,
    args,
)) {
    comptime store.assertStore(@TypeOf(s));

    var txn = try s.begin();
    defer txn.deinit();

    const result = try f(&txn, ctx, args);

    try txn.commit();
    return result;
}

fn TxnOf(comptime Store: type) type {
    return switch (@typeInfo(Store)) {
        .pointer => |p| p.child.Txn,
        else => Store.Txn,
    };
}
