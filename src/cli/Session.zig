const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const core = @import("core");
const logic = @import("logic");
const Sqlite = @import("store").Sqlite;
const StoreError = @import("store").Error;

const Context = @import("Context.zig");
const paths = @import("paths.zig");
const WorkspaceConfig = @import("WorkspaceConfig.zig");

ctx: *Context,
arena: Arena,
root: paths.Found,
cfg: ?WorkspaceConfig,
store: Sqlite,
ids: core.V7,
clock: core.Clock,
meta: core.Meta,
project_id: core.Uuid,
replica_id: core.ReplicaId,

const Session = @This();

pub const OpenError = error{ ConfigNotInitialized, StoreNotInitialized } ||
    std.Io.Cancelable ||
    Allocator.Error ||
    StoreError;

pub fn open(ctx: *Context, root: paths.Found) OpenError!Session {
    var cfg = WorkspaceConfig.read(ctx.io, ctx.gpa, root.dir) catch |err| blk: {
        ctx.diag.set(root.path, "", "WorkspaceConfig.read", err);
        break :blk null;
    } orelse return error.ConfigNotInitialized;
    errdefer cfg.deinit();

    var s = ctx.getStore(cfg.data.project_id) catch |err| blk: {
        ctx.diag.set("", "", "WorkspaceConfig.read", err);
        break :blk null;
    } orelse return error.StoreNotInitialized;
    errdefer s.deinit();

    var arena: Arena = .init(ctx.gpa);
    errdefer arena.deinit();

    var boot: logic.Context = .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .arena = arena.allocator(),
        .diag = &ctx.diag,
    };
    var m = try logic.withTxn(&s, &boot, .{}, logic.meta.read);
    m.project_name = try arena.allocator().dupe(u8, m.project_name);

    return .{
        .ctx = ctx,
        .arena = arena,
        .cfg = cfg,
        .root = root,
        .store = s,
        .ids = .{},
        .clock = .initFrom(m.last_hlc),
        .meta = m,
        .project_id = cfg.data.project_id,
        .replica_id = m.replica_id,
    };
}

pub fn close(self: *Session) !void {
    var ctx = self.logicCtx();
    try logic.withTxn(&self.store, &ctx, .{}, logic.meta.flush);

    self.arena.deinit();
    if (self.cfg) |*c| c.deinit();
    self.store.deinit();
}

pub fn create(ctx: *Context, root: paths.Found, project_id: core.Uuid, project_name: []const u8) OpenError!Session {
    var arena: Arena = .init(ctx.gpa);
    errdefer arena.deinit();

    var s = ctx.createStore(project_id) catch |err| {
        ctx.diag.set("", "", "Sqlite.create", err);
        return error.StoreNotInitialized;
    };
    errdefer {
        s.deinit();
        const path = paths.projectDb(ctx.gpa, ctx.environ, project_id) catch |err| blk: {
            std.log.warn("{t}: Unable to compute projectDb path for project {s}", .{ err, project_id.hex() });
            break :blk null;
        };

        if (path) |p| {
            Io.Dir.deleteFileAbsolute(ctx.io, p) catch |err| {
                std.log.warn("{t}: Unable to delete projectDb located at: {s}", .{ err, p });
            };
        }
    }

    const ids: core.V7 = .{};
    const replica_id = core.ReplicaId.generate(ctx.io);
    var boot: logic.Context = .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .arena = arena.allocator(),
        .diag = &ctx.diag,
        .replica_id = replica_id,
        .project_id = project_id,
    };
    var m = try logic.withTxn(&s, &boot, .{ .project_name = project_name }, logic.meta.create);
    m.project_name = try arena.allocator().dupe(u8, m.project_name);

    return .{
        .ctx = ctx,
        .arena = arena,
        .cfg = null,
        .root = root,
        .store = s,
        .ids = ids,
        .clock = .initFrom(m.last_hlc),
        .meta = m,
        .project_id = project_id,
        .replica_id = replica_id,
    };
}

pub fn attach(ctx: *Context, root: paths.Found, project_id: core.Uuid) OpenError!Session {
    var arena: Arena = .init(ctx.gpa);
    errdefer arena.deinit();

    var s = ctx.getStore(project_id) catch |err| {
        ctx.diag.set("", "", "Sqlite.open", err);
        return error.StoreNotInitialized;
    };
    errdefer s.deinit();

    const ids: core.V7 = .{};
    var boot: logic.Context = .{
        .io = ctx.io,
        .gpa = ctx.gpa,
        .arena = arena.allocator(),
        .diag = &ctx.diag,
    };
    var m = try logic.withTxn(&s, &boot, .{}, logic.meta.read);
    m.project_name = try arena.allocator().dupe(u8, m.project_name);

    return .{
        .ctx = ctx,
        .arena = arena,
        .cfg = null,
        .root = root,
        .store = s,
        .ids = ids,
        .clock = .initFrom(m.last_hlc),
        .meta = m,
        .project_id = project_id,
        .replica_id = m.replica_id,
    };
}

/// Build a context object for `logic`.
pub fn logicCtx(self: *Session) logic.Context {
    return .{
        .io = self.ctx.io,
        .gpa = self.ctx.gpa,
        .arena = self.arena.allocator(),
        .diag = &self.ctx.diag,
        .project_id = self.project_id,
        .replica_id = self.replica_id,
        .ids = &self.ids,
        .clock = &self.clock,
    };
}
