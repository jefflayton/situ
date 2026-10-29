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
const Session = @import("../Session.zig");
const WorkspaceConfig = @import("../WorkspaceConfig.zig");
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

const Inconsistency = union(enum) { MissingWorkspace, MissingStore: core.Uuid };

const State = union(enum) {
    fresh,
    initialized,
    inconsistent: Inconsistency,
};

pub fn run(ctx: *Context, _: *const Opts) cmd.CommandError!void {
    const io = ctx.io;
    const gpa = ctx.gpa;

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
                ctx.diag.fail(err, .{ .op = "init.realPathFileAlloc", .context = "cwd" }) catch {};
                return error.Io;
            },
            .linked = false,
        };
    }
    defer root.deinit(io, gpa);

    var project_id: core.Uuid = undefined;

    const p = probe(ctx, root) catch |err| {
        ctx.diag.fail(err, .{ .op = "init.probe" }) catch {};
        return error.Io;
    };
    switch (p) {
        .initialized => return error.AlreadyInitialized,
        .inconsistent => |i| switch (i) {
            .MissingStore => |p_id| {
                project_id = p_id;
            },
            .MissingWorkspace => {}, // TODO: handle missing workspace
        },
        .fresh => {},
    }

    var projects = try ctx.listProjects(&arena);
    defer projects.deinit();

    const project_names: [][]const u8 = try ctx.gpa.alloc([]const u8, projects.items.len);
    defer ctx.gpa.free(project_names);
    for (projects.items, 0..) |pr, i| project_names[i] = pr.name;

    const p_idx = try prompt.choose(ctx, []const u8, project_names, "Project");

    var session: Session = undefined;
    var project_name: []const u8 = undefined;
    if (p_idx) |i| {
        project_id = projects.items[i].id;
        project_name = projects.items[i].name;
        session = Session.attach(ctx, root, project_id) catch |err| {
            ctx.diag.fail(err, .{ .op = "init.Session.attach" }) catch {};
            return error.Io;
        };
    } else {
        var ids: core.V7 = .{};
        project_id = try ids.generate(ctx.io);
        session = Session.create(ctx, root, project_id, project_name) catch |err| {
            ctx.diag.fail(err, .{ .op = "init.Session.create" }) catch {};
            return error.Io;
        };
        project_name = try prompt.text(ctx, arena.allocator(), "Project Name");
    }
    try session.flush();
    defer session.close();

    var lc = session.logicCtx();
    const workspaces = try logic.withTxn(&session.store, &lc, .{}, logic.workspaces.list);

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
        wkspc_name = try prompt.text(ctx, arena.allocator(), "Workspace Name");
        const wkspc = try logic.withTxn(
            &session.store,
            &lc,
            .{ .name = wkspc_name, .path = root.path },
            logic.workspaces.createWithCheckout,
        );
        wkspc_id = wkspc.id;
    }

    if (session.cfg) |*c| {
        c.data.workspace_id = wkspc_id;
    } else {
        session.cfg = .{
            .arena = .init(gpa),
            .dir = root.dir,
            .data = .{ .project_id = project_id, .workspace_id = wkspc_id },
        };
    }
    session.cfg.?.write(io) catch |err| {
        var path: [std.fs.max_path_bytes]u8 = undefined;
        _ = session.cfg.?.dir.realPath(io, &path) catch {};
        ctx.diag.fail(err, .{ .op = "init.run.WorkspaceConfig.write", .context = &path }) catch {};
        return error.Io;
    };

    const git_dir: ?Io.Dir = root.dir.openDir(io, ".git", .{}) catch |err| switch (err) {
        error.FileNotFound => null, // TODO: record not found
        else => |e| {
            ctx.diag.fail(e, .{ .op = "init.run.root.openDir", .context = ".git" }) catch {};
            return error.Io;
        },
    };
    if (git_dir) |g| try appendExclude(ctx, g, "info/exclude", "/.situ/\n");

    if (try prompt.confirm(ctx, "Write .gitignore?")) {
        try appendExclude(ctx, root.dir, ".gitignore", "*.situ.*\n");
    }
}

fn probe(ctx: *Context, root: paths.Found) !State {
    var cfg = WorkspaceConfig.read(ctx.io, ctx.gpa, root.dir) catch |err| switch (err) {
        error.NotFound => null,
        else => |e| return e,
    };
    if (cfg) |*c| {
        defer c.deinit();

        var store = ctx.getStore(c.data.project_id) catch |err| switch (err) {
            error.NotFound => null,
            else => |e| return e,
        };
        if (store) |*s| {
            defer s.deinit();

            var arena: std.heap.ArenaAllocator = .init(ctx.gpa);
            defer arena.deinit();

            var lc: logic.Context = .{
                .io = ctx.io,
                .gpa = ctx.gpa,
                .arena = arena.allocator(),
            };
            _ = logic.withTxn(s, &lc, .{ .id = c.data.workspace_id }, logic.workspaces.read) catch |err| switch (err) {
                error.NotFound => return .{ .inconsistent = .MissingWorkspace },
                else => |e| return e,
            };

            return .initialized;
        }

        return .{ .inconsistent = .{ .MissingStore = c.data.project_id } };
    }

    return .fresh;
}

/// Appends a glob to the end of a git exlude file
/// TODO: make more generic. Probably move to paths.zig
fn appendExclude(ctx: *Context, dir: Io.Dir, path: []const u8, exclude: []const u8) cmd.CommandError!void {
    const data = dir.readFileAlloc(ctx.io, path, ctx.gpa, .unlimited) catch |err| switch (err) {
        error.FileNotFound => null,
        else => |e| {
            ctx.diag.fail(e, .{ .op = "init.appendExclude.readFileAlloc", .context = path }) catch {};
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
                ctx.diag.fail(err, .{ .op = "init.appendExclude.writeFile", .context = path }) catch {};
                return error.Io;
            };
        }
    }
}
