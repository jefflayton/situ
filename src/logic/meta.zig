const std = @import("std");
const core = @import("core");
const store = @import("store");
const logic = @import("root.zig");

pub fn createIfNotExists(txn: anytype, ctx: *logic.Ctx, args: anytype) !core.model.Meta {
    comptime store.assertTxn(@TypeOf(txn));

    const found_meta = try txn.getMeta();
    if (found_meta) |m| return m;

    return try create(txn, ctx, args);
}

pub fn create(txn: anytype, ctx: *logic.Ctx, args: anytype) !core.model.Meta {
    _ = args;
    comptime store.assertTxn(@TypeOf(txn));

    const zero: core.Ts = .{ .wall = 0 };
    const meta: core.model.Meta = .{
        .id = 1,
        .replica_id = ctx.replica_id.value,
        .last_hlc = zero.toString(),
    };

    try txn.insertMeta(meta);

    return meta;
}

pub fn flush(txn: anytype, ctx: *logic.Ctx, args: anytype) !void {
    _ = args;
    comptime store.assertTxn(@TypeOf(txn));

    try txn.updateMeta(ctx.clock.last);
}
