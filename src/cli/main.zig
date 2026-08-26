const std = @import("std");
const core = @import("core");
const logic = @import("logic");
const paths = @import("paths.zig");
const store = @import("store");

pub fn main(init: std.process.Init) !void {
    var s: store.Sqlite = try .init("/Users/jeffreylayton/dev/situ/app.db");
    defer s.deinit();

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
        &s,
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
    defer logic.withTxn(&s, &ctx, .{}, logic.meta.flush) catch |err| {
        std.log.warn("failed to persist last_hlc: {t}", .{err});
    };

    const project = try logic.withTxn(
        &s,
        &ctx,
        core.model.NewProject{ .name = "MyApp" },
        logic.projects.create,
    );
    std.log.debug("project: {any}", .{project});
}

test {
    _ = @import("paths.zig");
}
