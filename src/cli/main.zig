const std = @import("std");
const core = @import("core");
const logic = @import("logic");
const Sqlite = @import("store").Sqlite;

pub fn main(init: std.process.Init) !void {
    var store: Sqlite = try .init("/Users/jeffreylayton/dev/situ/app.db");
    defer store.deinit();

    const replica_id: core.ReplicaId = .generate(init.io);
    var ids: core.V7 = .{};
    var boot_clock: core.Clock = .{};
    var boot_ctx: logic.Ctx = .{
        .io = init.io,
        .replica_id = replica_id,
        .ids = &ids,
        .clock = &boot_clock,
    };

    const meta = try logic.withTxn(
        &store,
        &boot_ctx,
        .{},
        logic.meta.createIfNotExists,
    );
    std.log.debug("meta: {any}", .{meta});

    var clock: core.Clock = .initFrom(try core.Ts.parse(&meta.last_hlc));
    var ctx: logic.Ctx = .{
        .io = init.io,
        .replica_id = replica_id,
        .ids = &ids,
        .clock = &clock,
    };
    defer logic.withTxn(&store, &ctx, .{}, logic.meta.flush) catch |err| {
        std.log.warn("failed to persist last_hlc: {t}", .{err});
    };

    const project = try logic.withTxn(
        &store,
        &ctx,
        core.model.NewProject{ .name = "MyApp" },
        logic.projects.create,
    );
    std.log.debug("project: {any}", .{project});
}

fn TxnOf(comptime Store: type) type {
    return switch (@typeInfo(Store)) {
        .pointer => |p| p.child.Txn,
        else => Store.Txn,
    };
}
