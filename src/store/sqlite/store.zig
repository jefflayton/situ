const std = @import("std");
const Arena = std.heap.ArenaAllocator;
const ArrayList = std.array_list.Managed;

const core = @import("core");
const sqlite = @import("sqlite");

const store = @import("../root.zig");
const errors = @import("errors.zig");
const row = @import("row.zig");

pub const Sqlite = struct {
    db: sqlite.Db,

    pub fn init(path: [:0]const u8, diag: *core.Diagnostic) !Sqlite {
        var db = try open(path, diag);
        errdefer db.deinit();

        try migrate(&db, diag);
        return .{ .db = db };
    }

    pub fn deinit(self: *Sqlite) void {
        self.db.deinit();
    }

    pub fn begin(self: *Sqlite, gpa: std.mem.Allocator, diag: ?*core.Diagnostic) store.Error!Txn {
        self.db.exec("BEGIN", .{}, .{}) catch |err| return errors.capture(&self.db, err, "begin txn", diag);
        const arena: Arena = .init(gpa);
        return .{ .store = self, .done = false, .arena = arena, .diag = diag };
    }

    pub const Txn = struct {
        store: *Sqlite,
        done: bool,
        arena: Arena,
        diag: ?*core.Diagnostic,

        pub fn commit(self: *Txn) store.Error!void {
            self.store.db.exec("COMMIT", .{}, .{}) catch |err| return errors.capture(&self.store.db, err, "commit txn", self.diag);
            self.done = true;
        }

        pub fn deinit(self: *Txn) void {
            if (!self.done) self.store.db.exec("ROLLBACK", .{}, .{}) catch {};
            self.arena.deinit();
        }

        pub fn getMeta(self: *Txn) store.Error!core.Meta {
            var stmt = self.store.db.prepare(
                \\SELECT id, project_name, project_id, replica_id, last_hlc
                \\FROM meta
                \\WHERE id = 1
            ) catch |err| return errors.capture(&self.store.db, err, "prepare getMeta", self.diag);
            defer stmt.deinit();

            const found = stmt.oneAlloc(row.MetaRow, self.arena.allocator(), .{}, .{}) catch |err| {
                return errors.capture(&self.store.db, err, "execute getMeta", self.diag);
            };
            if (found) |f| return row.MetaRow.toMeta(f);
            return error.NotFound;
        }

        pub fn insertMeta(self: *Txn, meta: core.Meta) store.Error!void {
            self.store.db.execAlloc(
                self.arena.allocator(),
                \\INSERT INTO meta (id, project_name, project_id, replica_id, last_hlc)
                \\VALUES (?, ?, ?, ?, ?)
            ,
                .{},
                row.MetaRow.fromMeta(meta),
            ) catch |err| return errors.capture(&self.store.db, err, "execute insertMeta", self.diag);
        }

        pub fn updateMeta(self: *Txn, meta: core.Meta) store.Error!void {
            const m: row.MetaRow = .fromMeta(meta);

            self.store.db.execAlloc(
                self.arena.allocator(),
                \\UPDATE meta
                \\SET last_hlc = ?
                \\WHERE id = 1
            ,
                .{},
                .{ .last_hlc = m.last_hlc },
            ) catch |err| return errors.capture(&self.store.db, err, "execute updateMeta", self.diag);
        }

        pub fn getWorkspace(self: *Txn, id: core.Uuid) store.Error!core.Workspace {
            var stmt = self.store.db.prepare(
                \\SELECT id, name, created_ts, updated_hlc
                \\FROM workspaces
                \\WHERE id = ?
                ,
            ) catch |err| return errors.capture(&self.store.db, err, "prepare getWorkspace", self.diag);
            defer stmt.deinit();

            const found = stmt.oneAlloc(
                row.WorkspaceRow,
                self.arena.allocator(),
                .{},
                .{ .id = row.UuidCol.fromUuid(id) },
            ) catch |err| {
                return errors.capture(&self.store.db, err, "execute getWorkspace", self.diag);
            };
            if (found) |f| return row.WorkspaceRow.toWorkspace(f);
            return error.NotFound;
        }

        pub fn listWorkspaces(self: *Txn) store.Error![]core.Workspace {
            var stmt = self.store.db.prepare(
                \\SELECT id, name, created_ts, updated_hlc
                \\FROM workspaces
            ) catch |err| return errors.capture(&self.store.db, err, "prepare listWorkspaces", self.diag);
            defer stmt.deinit();

            const rows = stmt.all(row.WorkspaceRow, self.arena.allocator(), .{}, .{}) catch |err| {
                return errors.capture(&self.store.db, err, "execute listWorkspaces", self.diag);
            };

            var new_rows: ArrayList(core.Workspace) = .init(self.arena.allocator());
            for (rows) |r| try new_rows.append(r.toWorkspace());
            return try new_rows.toOwnedSlice();
        }

        pub fn insertWorkspace(self: *Txn, w: core.Workspace) store.Error!void {
            self.store.db.execAlloc(
                self.arena.allocator(),
                \\INSERT INTO workspaces(id, name, created_ts, updated_hlc)
                \\VALUES (?, ?, ?, ?)
            ,
                .{},
                row.WorkspaceRow.fromWorkspace(w),
            ) catch |err| return errors.capture(&self.store.db, err, "insertWorkspace", self.diag);
        }

        pub fn insertCheckout(self: *Txn, c: core.Checkout) store.Error!void {
            self.store.db.execAlloc(
                self.arena.allocator(),
                \\INSERT INTO checkouts(workspace_id, path)
                \\VALUES (?, ?)
            ,
                .{},
                row.CheckoutRow.fromCheckout(c),
            ) catch |err| return errors.capture(&self.store.db, err, "insertCheckout", self.diag);
        }
    };
};

/// Opens a store.db and initiates a sqlite session
fn open(path: [:0]const u8, diag: *core.Diagnostic) store.Error!sqlite.Db {
    var db = sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .SingleThread,
    }) catch |err| return errors.classify(err);
    errdefer db.deinit();

    _ = db.pragma(i64, .{}, "busy_timeout", "5000") catch |err| {
        return errors.capture(&db, err, "pragma set busy_timeout", diag);
    };

    const mode = db.pragma([16:0]u8, .{}, "journal_mode", "wal") catch |err| {
        return errors.capture(&db, err, "pragma set journal_mode", diag);
    };
    if (mode == null or !std.mem.eql(u8, std.mem.sliceTo(&mode.?, 0), "wal")) {
        return error.Io;
    }

    _ = db.pragma(i64, .{}, "synchronous", "normal") catch |err| {
        return errors.capture(&db, err, "pragma set synchronous", diag);
    };
    _ = db.pragma(i64, .{}, "foreign_keys", "on") catch |err| {
        return errors.capture(&db, err, "pragma set foreign_keys", diag);
    };

    return db;
}

const migrations = [_]Migration{
    .{ .version = 1, .sql = @embedFile("migrations/0001_init.sql") },
};

const Migration = struct { version: i32, sql: [:0]const u8 };

fn latestVersion() i32 {
    return migrations[migrations.len - 1].version;
}

/// Runs all migrations, up to the latest version.
fn migrate(db: *sqlite.Db, diag: *core.Diagnostic) store.Error!void {
    db.exec("BEGIN IMMEDIATE", .{}, .{}) catch |err| {
        return errors.capture(db, err, "migrate begin", diag);
    };
    errdefer db.exec("ROLLBACK", .{}, .{}) catch {};

    const current = (db.pragma(i32, .{}, "user_version", null) catch |err| {
        return errors.capture(db, err, "pragma get user_version", diag);
    }) orelse 0;
    if (current > latestVersion()) return error.Migration;

    inline for (migrations) |m| {
        if (m.version > current) {
            try execScript(db, m.sql, diag);
        }
    }
    _ = db.pragma(i32, .{}, "user_version", comptime std.fmt.comptimePrint("{d}", .{latestVersion()})) catch |err| {
        return errors.capture(db, err, "pragma set user_version", null);
    };
    db.exec("COMMIT", .{}, .{}) catch |err| return errors.capture(db, err, "migrate commit", null);
}

/// Run a SQL script with sqlite3
/// zig-sqlite3 doesn't have a wrapper for sqlite3_exec
fn execScript(db: *sqlite.Db, sql: [:0]const u8, diag: ?*core.Diagnostic) store.Error!void {
    var err_msg: [*c]u8 = null;
    const rc = sqlite.c.sqlite3_exec(db.db, sql.ptr, null, null, &err_msg);
    if (rc == sqlite.c.SQLITE_OK) return;

    defer if (err_msg != null) sqlite.c.sqlite3_free(err_msg);
    if (diag) |d| {
        d.op = "execute migration";
        if (err_msg != null) d.setDetail(std.mem.span(err_msg));
        d.cause = null;
    }
    return errors.classifyCode(rc);
}

test {
    _ = @import("row.zig");
}
