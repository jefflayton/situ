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

io: Io,
gpa: Allocator,
environ: *Environ,
diag: core.Diagnostic = .{},
stdin: *Io.Reader,
stdout: *Io.Writer,
stderr: *Io.Writer,

pub const Error = error{BadPath} ||
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
            self.diag.set(dir_path, "", "create directory", e);
            return e;
        },
    };
    const dir = Io.Dir.openDirAbsolute(self.io, dir_path, .{}) catch |err| {
        self.diag.set(dir_path, "", "open directory", err);
        return err;
    };
    defer dir.close(self.io);

    const cfg = try Config.read(self.io, self.gpa, dir);
    if (cfg) |c| return c;

    var new_cfg: Config = .{ .arena = .init(self.gpa), .data = .{}, .dir = dir };
    try new_cfg.write(self.io);

    return new_cfg;
}

/// Gets the store for the current project, creating one if it doesn't exist.
pub fn getStore(self: *Context, id: core.Uuid) !store.Sqlite {
    const path = try paths.projectDb(self.gpa, self.environ, id);
    defer self.gpa.free(path);

    Io.Dir.accessAbsolute(self.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const dir_path = std.fs.path.dirname(path) orelse return error.BadPath;
            const dir = Io.Dir.cwd().createDirPathOpen(self.io, dir_path, .{}) catch |e| {
                self.diag.set(path, "", "open directory", e);
                return e;
            };
            defer dir.close(self.io);

            var atomic = dir.createFileAtomic(self.io, path, .{}) catch |e| {
                self.diag.set(path, "", "create file", e);
                return e;
            };
            defer atomic.deinit(self.io);
            atomic.link(self.io) catch |e| {
                self.diag.set(path, "", "link file", e);
                return e;
            };
        },
        else => |e| return e,
    };

    return try store.Sqlite.init(path, &self.diag);
}

const Project = struct {
    id: core.Uuid,
    name: []const u8,
};

/// List all projects
pub fn listProjects(self: *Context) Error!ArrayList(Project) {
    var found = try paths.projectsDir(self.io, self.gpa, self.environ);
    defer found.deinit(self.io, self.gpa);

    var walker = found.dir.walkSelectively(self.gpa) catch |err| {
        self.diag.set(found.path, "", "walk dir", err);
        return err;
    };
    defer walker.deinit();

    var project_ids: ArrayList(Project) = .init(self.gpa);
    while (walker.next(self.io) catch |err| {
        self.diag.set(found.path, "", "iterate dir", err);
        return err;
    }) |entry| {
        if (entry.kind != .directory) continue;

        const uuid = core.Uuid.parse(entry.basename) catch |err| {
            self.diag.set(found.path, entry.basename, "parse uuid", err);
            return err;
        };

        var s = try self.getStore(uuid);
        defer s.deinit();

        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        var ctx: logic.Context = .{
            .io = self.io,
            .gpa = self.gpa,
            .arena = arena.allocator(),
            .project_id = uuid,
        };
        const meta = try logic.withTxn(&s, &ctx, .{}, logic.meta.read);

        try project_ids.append(.{
            .id = uuid,
            .name = meta.project_name,
        });
    }

    return project_ids;
}
