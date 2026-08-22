const std = @import("std");
const core = @import("core");
const logic = @import("logic");
const Sqlite = @import("store").Sqlite;

pub fn main(init: std.process.Init) !void {
    var store: Sqlite = try .init("/Users/jeffreylayton/dev/situ/app.db");
    defer store.deinit();

    var v7: core.V7 = .{};
    var ctx: logic.Ctx = .{
        .replica = .generate(init.io),
        .ids = &v7,
        .io = init.io,
    };

    const project = try logic.projects.init(&store, &ctx, .{ .name = "MyApp" });
    std.log.debug("project: {any}", .{project});
}
