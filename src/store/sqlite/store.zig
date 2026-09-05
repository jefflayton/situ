const std = @import("std");
const Arena = std.heap.ArenaAllocator;

const core = @import("core");
const sqlite = @import("sqlite");

const row = @import("row.zig");

pub const Sqlite = struct {
    db: sqlite.Db,

    pub fn init(path: [:0]const u8) !Sqlite {
        var db = try open(path);
        errdefer db.deinit();

        try migrate(&db);
        return .{ .db = db };
    }

    pub fn deinit(self: *Sqlite) void {
        self.db.deinit();
    }

    pub fn begin(self: *Sqlite, gpa: std.mem.Allocator) !Txn {
        try self.db.exec("BEGIN", .{}, .{});
        const arena: Arena = .init(gpa);
        return .{ .store = self, .done = false, .arena = arena };
    }

    pub const Txn = struct {
        store: *Sqlite,
        done: bool,
        arena: Arena,

        pub fn commit(self: *Txn) !void {
            try self.store.db.exec("COMMIT", .{}, .{});
            self.done = true;
        }

        pub fn deinit(self: *Txn) void {
            if (!self.done) self.store.db.exec("ROLLBACK", .{}, .{}) catch {};
            self.arena.deinit();
        }

        pub fn getMeta(self: *Txn) !?core.model.Meta {
            var stmt = try self.store.db.prepare(
                \\SELECT id, project_id, replica_id, last_hlc
                \\FROM meta
                \\WHERE id = 1
            );
            defer stmt.deinit();

            const found = try stmt.oneAlloc(row.MetaRow, self.arena.allocator(), .{}, .{});
            if (found) |f| return row.MetaRow.toMeta(f);
            return null;
        }

        pub fn insertMeta(self: *Txn, meta: core.model.Meta) !void {
            try self.store.db.execAlloc(
                self.arena.allocator(),
                \\INSERT INTO meta (id, project_id, replica_id, last_hlc)
                \\VALUES (?, ?, ?, ?)
            ,
                .{},
                row.MetaRow.fromMeta(meta),
            );
        }

        pub fn updateMeta(self: *Txn, meta: core.model.Meta) !void {
            const m: row.MetaRow = .fromMeta(meta);

            try self.store.db.execAlloc(
                self.arena.allocator(),
                \\UPDATE meta
                \\SET last_hlc = ?
                \\WHERE id = 1
            ,
                .{},
                .{ .last_hlc = m.last_hlc },
            );
        }
    };
};

/// Opens a store.db and initiates a sqlite session
fn open(path: [:0]const u8) !sqlite.Db {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .SingleThread,
    });
    errdefer db.deinit();

    _ = try db.pragma(i64, .{}, "busy_timeout", "5000");

    const mode = try db.pragma([16:0]u8, .{}, "journal_mode", "wal");
    if (mode == null or !std.mem.eql(u8, std.mem.sliceTo(&mode.?, 0), "wal")) {
        return error.WalUnavailable;
    }

    _ = try db.pragma(i64, .{}, "synchronous", "normal");
    _ = try db.pragma(i64, .{}, "foreign_keys", "on");

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
fn migrate(db: *sqlite.Db) !void {
    try db.exec("BEGIN IMMEDIATE", .{}, .{});
    errdefer db.exec("ROLLBACK", .{}, .{}) catch |err| {
        std.log.err("failed to run rollback: {}", .{err});
    };

    const current = (try db.pragma(i32, .{}, "user_version", null)) orelse 0;
    if (current > latestVersion()) return error.DbNewerThanBinary;

    inline for (migrations) |m| {
        if (m.version > current) {
            try execScript(db, m.sql);
        }
    }
    _ = try db.pragma(i32, .{}, "user_version", comptime std.fmt.comptimePrint("{d}", .{latestVersion()}));
    try db.exec("COMMIT", .{}, .{});
}

/// Run a SQL script with sqlite3
/// zig-sqlite3 doesn't have a wrapper for sqlite3_exec
fn execScript(db: *sqlite.Db, sql: [:0]const u8) !void {
    var err_msg: [*c]u8 = null;
    const rc = sqlite.c.sqlite3_exec(db.db, sql.ptr, null, null, &err_msg);
    if (rc != sqlite.c.SQLITE_OK) {
        defer if (err_msg != null) sqlite.c.sqlite3_free(err_msg);
        std.log.err("migration failed: {s}", .{err_msg});
        return error.MigrationFailed;
    }
}

test {
    _ = @import("row.zig");
}
