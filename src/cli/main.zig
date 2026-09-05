const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ.Map;
const ArrayList = std.array_list.Managed;

const core = @import("core");
const logic = @import("logic");
const store = @import("store");

const Config = @import("Config.zig");
const paths = @import("paths.zig");
const WorkspaceConfig = @import("WorkspaceConfig.zig");

const BUF_SIZE = 256;
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const environ = init.environ_map;

    var root = try paths.findWorkspaceRoot(io, gpa, .cwd());
    if (root) |*r| {
        defer r.deinit(io, gpa);

        if (r.linked) {
            std.log.err("checkout of <project>", .{});
        } else {
            std.log.err("already initialized", .{});
        }

        std.process.exit(1);
        return;
    }

    // var project_name = "Situ";
    const project_id: core.Uuid = .{ .bytes = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 } };

    var s = try getStore(io, gpa, environ, project_id);
    defer s.deinit();

    const replica_id: core.ReplicaId = .generate(io);
    var ids: core.V7 = .{};
    var boot_clock: core.Clock = .{};
    var boot_ctx: logic.Ctx = .{
        .io = io,
        .project_id = project_id,
        .replica_id = replica_id,
        .ids = &ids,
        .clock = &boot_clock,
        .gpa = gpa,
    };

    const meta = try logic.withTxn(
        &s,
        &boot_ctx,
        .{},
        logic.meta.createIfNotExists,
    );

    var clock: core.Clock = .initFrom(meta.last_hlc);
    var ctx: logic.Ctx = .{
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
    // std.log.debug("meta: {any}", .{meta});

    // var cfg = try getConfig(io, gpa, environ);
    // defer cfg.deinit();

    // var local_cfg = try WorkspaceConfig.read(io, gpa, .cwd()) orelse return error.InvalidConfig;
    // defer local_cfg.deinit();

    //
    // const project = try logic.withTxn(
    //     &s,
    //     &ctx,
    //     core.model.NewProject{ .name = "MyApp" },
    //     logic.projects.create,
    // );
    // std.log.debug("project: {any}", .{project});
}

/// Gets the global config.toml, creating one if it doesn't exist.
fn getConfig(io: Io, gpa: Allocator, environ: *Environ) !Config {
    const path = try paths.configToml(gpa, environ);
    defer gpa.free(path);

    const dir_path = std.fs.path.dirname(path) orelse return error.BadPath;
    Io.Dir.createDirAbsolute(io, dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };
    const dir = try Io.Dir.openDirAbsolute(io, dir_path, .{});
    defer dir.close(io);

    const cfg = try Config.read(io, gpa, dir);
    if (cfg) |c| return c;

    var new_cfg: Config = .{ .arena = .init(gpa), .data = .{}, .dir = dir };
    try new_cfg.write(io);

    return new_cfg;
}

/// Gets the store for the current project, creating one if it doesn't exist.
fn getStore(io: Io, gpa: Allocator, environ: *Environ, id: core.Uuid) !store.Sqlite {
    const path = try paths.projectDb(gpa, environ, id);
    defer gpa.free(path);

    Io.Dir.accessAbsolute(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const dir_path = std.fs.path.dirname(path) orelse return error.BadPath;
            const dir = try Io.Dir.cwd().createDirPathOpen(io, dir_path, .{});
            defer dir.close(io);

            var atomic = try dir.createFileAtomic(io, path, .{});
            defer atomic.deinit(io);
            try atomic.link(io);
        },
        else => |e| return e,
    };

    return try .init(path);
}

test {
    _ = @import("paths.zig");
    _ = @import("WorkspaceConfig.zig");
}
