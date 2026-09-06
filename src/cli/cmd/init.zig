const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ.Map;
const ArrayList = std.array_list.Managed;
const ArgsIter = std.process.Args.Iterator;

const core = @import("core");
const logic = @import("logic");

const cmd = @import("root.zig");

const Context = @import("../Context.zig");
const paths = @import("../paths.zig");

pub fn run(context: *Context, _: *ArgsIter) cmd.CommandError!void {
    const io = context.io;
    const gpa = context.gpa;

    var root = try paths.findWorkspaceRoot(io, gpa, .cwd(), &context.diag);
    if (root) |*r| {
        defer r.deinit(io, gpa);
        return if (r.linked) error.LinkedCheckout else error.AlreadyInitialized;
    }

    var project_ids = try context.listProjects();
    defer project_ids.deinit();

    std.debug.print("project_ids:\n", .{});
    for (project_ids.items) |p| {
        std.debug.print("  {s}: {s}\n", .{ p.id.hex(), p.name });
    }

    var ids: core.V7 = .{};
    const project_name = "Situ";
    const project_id = try ids.generate(io);

    var s = try context.getStore(project_id);
    defer s.deinit();

    const replica_id: core.ReplicaId = .generate(io);
    var boot_clock: core.Clock = .{};
    var boot_ctx: logic.Context = .{
        .io = io,
        .gpa = gpa,
        .project_id = project_id,
        .replica_id = replica_id,
        .ids = &ids,
        .clock = &boot_clock,
    };

    const meta = try logic.withTxn(
        &s,
        &boot_ctx,
        .{ .project_name = project_name },
        logic.meta.createIfNotExists,
    );

    var clock: core.Clock = .initFrom(meta.last_hlc);
    var ctx: logic.Context = .{
        .io = io,
        .project_id = project_id,
        .replica_id = replica_id,
        .ids = &ids,
        .clock = &clock,
        .gpa = gpa,
    };
    defer logic.withTxn(&s, &ctx, .{}, logic.meta.flush) catch |err| {
        std.log.warn("failed to persist last_hlc: {t}", .{err});
    };
}
