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
const prompt = @import("../prompt.zig");

pub const Opts = struct {
    // no flags yet
    help: bool = false,

    pub const flags = .{
        .help = .{ .short = 'h', .about = "Print help" },
    };

    pub const about: []const u8 = "Initialize a Situ workspace in the current directory";
    pub const usage: []const u8 = "[OPTIONS]";
};

pub fn run(ctx: *Context, _: *const Opts) cmd.CommandError!void {
    const io = ctx.io;
    const gpa = ctx.gpa;
    var ids: core.V7 = .{};
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    const found_root = try paths.findWorkspaceRoot(io, gpa, .cwd(), &ctx.diag);

    var root: paths.Found = undefined;
    if (found_root) |f| {
        root = f;
    } else {
        root = paths.Found{
            .dir = try Io.Dir.openDir(.cwd(), io, ".", .{}),
            .path = Io.Dir.realPathFileAlloc(.cwd(), io, ".", gpa) catch |err| {
                ctx.diag.set("cwd", "", "realPath", err);
                return error.Io;
            },
            .linked = false,
        };
    }
    defer root.deinit(io, gpa);

    var projects = try ctx.listProjects();
    defer projects.deinit();

    const project_names: [][]const u8 = try ctx.gpa.alloc([]const u8, projects.items.len);
    defer ctx.gpa.free(project_names);
    for (projects.items, 0..) |p, i| project_names[i] = p.name;

    const p_idx = try prompt.choose(ctx, []const u8, project_names, "Project");

    var project_id: core.Uuid = undefined;
    var project_name: []const u8 = undefined;
    if (p_idx) |i| {
        project_id = projects.items[i].id;
        project_name = projects.items[i].name;
    } else {
        project_id = try ids.generate(io);
        project_name = try prompt.text(ctx, arena.allocator(), "Project Name");
    }

    var s = try ctx.getStore(project_id);
    defer s.deinit();

    const replica_id: core.ReplicaId = .generate(io);
    var boot_clock: core.Clock = .{};
    var boot_ctx: logic.Context = .{
        .io = io,
        .gpa = gpa,
        .arena = arena.allocator(),
        .diag = &ctx.diag,
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
    var txn_ctx: logic.Context = .{
        .io = io,
        .gpa = gpa,
        .arena = arena.allocator(),
        .diag = &ctx.diag,
        .project_id = project_id,
        .replica_id = replica_id,
        .ids = &ids,
        .clock = &clock,
    };
    defer logic.withTxn(&s, &txn_ctx, .{}, logic.meta.flush) catch |err| {
        std.log.warn("failed to persist last_hlc: {t}", .{err});
    };

    const workspaces = try logic.withTxn(&s, &txn_ctx, .{}, logic.workspaces.list);

    var wkspc_names: [][]const u8 = try ctx.gpa.alloc([]const u8, workspaces.len);
    defer ctx.gpa.free(wkspc_names);
    for (workspaces, 0..) |w, i| wkspc_names[i] = w.name;

    const w_idx = try prompt.choose(ctx, []const u8, wkspc_names, "Workspace");

    var wkspc_id: core.Uuid = undefined;
    var wkspc_name: []const u8 = undefined;
    if (w_idx) |i| {
        wkspc_id = workspaces[i].id;
        wkspc_name = workspaces[i].name;
    } else {
        wkspc_id = try ids.generate(io);
        wkspc_name = try prompt.text(ctx, arena.allocator(), "Workspace Name");
        try logic.withTxn(
            &s,
            &txn_ctx,
            .{ .name = wkspc_name, .path = root.path },
            logic.workspaces.createWithCheckout,
        );
    }

    const git_dir: ?Io.Dir = root.dir.openDir(io, ".git", .{}) catch |err| switch (err) {
        error.FileNotFound => null, // TODO: record not found
        else => |e| {
            ctx.diag.set(".git", "", "dir.access", e);
            return error.Io;
        },
    };
    if (git_dir) |g| try appendExclude(ctx, g, "info/exclude", "/.situ/\n");

    if (try prompt.confirm(ctx, "Write .gitignore?")) {
        try appendExclude(ctx, root.dir, ".gitignore", "*.situ.*\n");
    }
}

/// Appends a glob to the end of a git exlude file
/// TODO: make more generic. Probably move to paths.zig
fn appendExclude(ctx: *Context, dir: Io.Dir, path: []const u8, exclude: []const u8) cmd.CommandError!void {
    const data = dir.readFileAlloc(ctx.io, path, ctx.gpa, .unlimited) catch |err| switch (err) {
        error.FileNotFound => null,
        else => |e| {
            ctx.diag.set(path, "", "appendExclude.readFileAlloc", e);
            return error.Io;
        },
    };
    if (data) |d| {
        defer ctx.gpa.free(d);
        if (std.mem.indexOf(u8, d, exclude) == null) {
            var new = try ctx.gpa.alloc(u8, d.len + exclude.len);
            defer ctx.gpa.free(new);
            @memcpy(new[0..d.len], d);
            @memcpy(new[d.len..], exclude);

            dir.writeFile(ctx.io, .{ .sub_path = path, .data = new }) catch |err| {
                ctx.diag.set(path, "", "appendExclude.writeFile", err);
                return error.Io;
            };
        }
    }
}
