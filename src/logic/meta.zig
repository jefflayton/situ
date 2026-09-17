const std = @import("std");

const core = @import("core");
const store = @import("store");

const logic = @import("root.zig");

pub fn createIfNotExists(txn: anytype, ctx: *logic.Context, args: anytype) store.Error!core.Meta {
    comptime store.assertTxn(@TypeOf(txn));

    return txn.getMeta() catch |err| switch (err) {
        error.NotFound => try create(txn, ctx, args),
        else => |e| return e,
    };
}

pub fn read(txn: anytype, _: *logic.Context, _: anytype) store.Error!core.Meta {
    comptime store.assertTxn(@TypeOf(txn));

    return try txn.getMeta();
}

pub fn create(txn: anytype, ctx: *logic.Context, args: anytype) store.Error!core.Meta {
    comptime store.assertTxn(@TypeOf(txn));

    const zero: core.Ts = .{ .wall = 0 };
    const meta: core.Meta = .{
        .id = 1,
        .project_name = args.project_name,
        .project_id = ctx.project_id.?,
        .replica_id = ctx.replica_id.?,
        .last_hlc = zero,
    };

    try txn.insertMeta(meta);

    return meta;
}

pub fn flush(txn: anytype, ctx: *logic.Context, _: anytype) store.Error!void {
    comptime store.assertTxn(@TypeOf(txn));

    const meta: core.Meta = .{
        .id = 1,
        .project_name = undefined,
        .project_id = ctx.project_id.?,
        .replica_id = ctx.replica_id.?,
        .last_hlc = ctx.clock.?.last,
    };

    try txn.updateMeta(meta);
}
