const std = @import("std");
const core = @import("core");
const Ctx = @import("root.zig").Ctx;

pub fn init(store: anytype, ctx: *Ctx, draft: core.model.NewProject) !core.model.Project {
    var txn = try store.begin();
    defer txn.deinit();

    const project = try add(&txn, ctx, draft);

    try txn.commit();

    return project;
}

pub fn add(txn: anytype, ctx: *Ctx, draft: core.model.NewProject) !core.model.Project {
    const id = try ctx.ids.generate(ctx.io);
    const hlc = std.Io.Timestamp.now(ctx.io, .real).toMilliseconds();

    const project: core.model.Project = .{
        .id = id,
        .name = draft.name,
        .created_ts = hlc,
        .updated_ts = hlc,
    };
    try txn.insertProject(project);

    return project;
}
