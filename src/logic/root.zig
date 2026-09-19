const std = @import("std");

const core = @import("core");
const store = @import("store");

pub const meta = @import("meta.zig");
pub const workspaces = @import("workspaces.zig");
pub const checkouts = @import("checkouts.zig");

pub const Context = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    project_id: ?core.Uuid = null,
    replica_id: ?core.ReplicaId = null,
    ids: ?*core.V7 = null,
    clock: ?*core.Clock = null,
    diag: ?*core.Diagnostic = null,
};

pub fn withTxn(
    s: anytype,
    ctx: *Context,
    args: anytype,
    comptime f: anytype,
) !Payload(@TypeOf(f(
    @as(*TxnOf(@TypeOf(s)), undefined),
    ctx,
    args,
))) {
    comptime store.assertStore(@TypeOf(s));

    var txn = try s.begin(ctx.arena, ctx.diag);
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

fn Payload(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .error_union => |eu| eu.payload,
        else => T,
    };
}
