const std = @import("std");
const core = @import("core");
const store = @import("store");
const logic = @import("root.zig");

pub fn create(txn: anytype, ctx: *logic.Ctx, draft: core.model.NewProject) !core.model.Project {
    comptime store.assertTxn(@TypeOf(txn));

    const project = try add(txn, ctx, draft);
    // TODO: create "inbox" workspace

    return project;
}

pub fn add(txn: anytype, ctx: *logic.Ctx, draft: core.model.NewProject) !core.model.Project {
    comptime store.assertTxn(@TypeOf(txn));

    const id = try ctx.ids.generate(ctx.io);
    const ts = try ctx.clock.now(ctx.io);

    const project: core.model.Project = .{
        .id = id,
        .name = draft.name,
        .created_ts = ts.wall,
        .updated_hlc = ts.toString(),
    };
    try txn.insertProject(project);

    return project;
}
