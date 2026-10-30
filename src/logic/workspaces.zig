const std = @import("std");

const core = @import("core");
const store = @import("store");

const logic = @import("root.zig");

pub fn read(txn: anytype, _: *logic.Context, args: anytype) store.Error!core.Workspace {
    comptime store.assertTxn(@TypeOf(txn));

    return try txn.getWorkspace(args.id);
}

pub fn list(txn: anytype, ctx: *logic.Context, _: anytype) store.Error![]core.Workspace {
    comptime store.assertTxn(@TypeOf(txn));

    const rows = try txn.listWorkspaces();

    const out = try ctx.arena.alloc(core.Workspace, rows.len);
    for (rows, out) |r, *o| {
        o.* = r;
        o.name = try ctx.arena.dupe(u8, r.name);
    }
    return out;
}

pub fn create(txn: anytype, ctx: *logic.Context, args: anytype) store.Error!void {
    comptime store.assertTxn(@TypeOf(txn));

    const w = try buildWorkspace(ctx, args);
    try txn.insertWorkspace(w);
}

pub fn createWithCheckout(txn: anytype, ctx: *logic.Context, args: anytype) store.Error!core.Workspace {
    comptime store.assertTxn(@TypeOf(txn));

    const w = try buildWorkspace(ctx, args);
    try txn.insertWorkspace(w);

    try logic.checkouts.create(txn, ctx, .{ .workspace_id = w.id, .path = args.path });

    return w;
}

fn buildWorkspace(ctx: *logic.Context, args: anytype) store.Error!core.Workspace {
    const now = ctx.clock.?.now(ctx.io) catch |err| {
        if (ctx.diag) |d| d.fail(err, .{ .op = "logic.workspaces.create", .context = "clock.generate" });
        return error.Io;
    };
    const id = ctx.ids.?.generate(ctx.io) catch |err| {
        if (ctx.diag) |d| d.fail(err, .{ .op = "logic.workspaces.create", .context = "ids.generate" });
        return error.Io;
    };

    return .{
        .id = id,
        .name = args.name,
        .created_ts = now.wall,
        .updated_hlc = now,
    };
}
