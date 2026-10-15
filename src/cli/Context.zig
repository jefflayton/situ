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
const Session = @import("Session.zig");
const WorkspaceConfig = @import("WorkspaceConfig.zig");

io: Io,
gpa: Allocator,
environ: *Environ,
diag: core.Diagnostic,
stdin: *Io.Reader,
stdout: *Io.Writer,
stderr: *Io.Writer,

pub const Error = error{ BadPath, StoreNotFound } ||
    store.Error ||
    paths.Error ||
    core.Uuid.ParseError ||
    Allocator.Error ||
    Io.Cancelable ||
    Io.Dir.AccessError ||
    std.Io.Dir.CreateFileAtomicError ||
    std.Io.File.Atomic.LinkError;

const Context = @This();

/// Gets the global config.toml, creating one if it doesn't exist.
pub fn getConfig(self: *Context) !Config {
    const path = try paths.configToml(self.gpa, self.environ);
    defer self.gpa.free(path);

    const dir_path = std.fs.path.dirname(path) orelse return error.BadPath;
    Io.Dir.createDirAbsolute(self.io, dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| {
            return self.diag.fail(e, .{ .op = "getConfig.createDirAbsolute", .context = dir_path });
        },
    };
    const dir = Io.Dir.openDirAbsolute(self.io, dir_path, .{}) catch |err| {
        return self.diag.fail(err, .{ .op = "getConfig.openDirAbsolute", .context = dir_path });
    };
    defer dir.close(self.io);

    const cfg = try Config.read(self.io, self.gpa, dir);
    if (cfg) |c| return c;

    var new_cfg: Config = .{ .arena = .init(self.gpa), .data = .{}, .dir = dir };
    try new_cfg.write(self.io);

    return new_cfg;
}

/// Gets the store for the current project
pub fn getStore(self: *Context, id: core.Uuid) !store.Sqlite {
    const path = try paths.projectDb(self.gpa, self.environ, id);
    defer self.gpa.free(path);

    Io.Dir.accessAbsolute(self.io, path, .{ .read = true }) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => |e| return e,
    };

    return try store.Sqlite.init(path, &self.diag);
}

/// Creates a new store for the existing project;
pub fn createStore(self: *Context, id: core.Uuid) !store.Sqlite {
    const path = try paths.projectDb(self.gpa, self.environ, id);
    defer self.gpa.free(path);

    const dir_path = std.fs.path.dirname(path) orelse return error.BadPath;
    const dir = Io.Dir.cwd().createDirPathOpen(self.io, dir_path, .{}) catch |e| {
        return self.diag.fail(e, .{ .op = "createStore.createDirPathOpen", .context = path });
    };
    defer dir.close(self.io);

    var atomic = dir.createFileAtomic(self.io, path, .{}) catch |e| {
        return self.diag.fail(e, .{ .op = "createStore.createFileAtomic", .context = path });
    };
    defer atomic.deinit(self.io);
    atomic.link(self.io) catch |e| {
        return self.diag.fail(e, .{ .op = "createStore.atomic.link", .context = path });
    };

    return try store.Sqlite.init(path, &self.diag);
}

const Project = struct {
    id: core.Uuid,
    name: []const u8,
};

/// List all projects
pub fn listProjects(self: *Context, arena: *std.heap.ArenaAllocator) Error!ArrayList(Project) {
    var found = try paths.projectsDir(self.io, self.gpa, self.environ);
    defer found.deinit(self.io, self.gpa);

    var walker = found.dir.walkSelectively(self.gpa) catch |err| {
        return self.diag.fail(err, .{ .op = "listProjects.walkSelectively", .context = found.path });
    };
    defer walker.deinit();

    var projects: ArrayList(Project) = .init(self.gpa);
    while (walker.next(self.io) catch |err| {
        return self.diag.fail(err, .{ .op = "listProjects.walker.next", .context = found.path });
    }) |entry| {
        if (entry.kind != .directory) continue;

        const uuid = core.Uuid.parse(entry.basename) catch |err| {
            return self.diag.fail(err, .{ .op = "listProjects.Uuid.parse", .context = entry.basename });
        };

        var s = try self.getStore(uuid);
        defer s.deinit();

        var ctx: logic.Context = .{
            .io = self.io,
            .gpa = self.gpa,
            .arena = arena.allocator(),
            .project_id = uuid,
        };
        const meta = logic.withTxn(&s, &ctx, .{}, logic.meta.read) catch |err| switch (err) {
            error.NotFound => continue,
            else => |e| return e,
        };

        try projects.append(.{
            .id = uuid,
            .name = try arena.allocator().dupe(u8, meta.project_name),
        });
    }

    return projects;
}
