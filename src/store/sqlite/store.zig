const std = @import("std");
const core = @import("core");
const sqlite = @import("sqlite");

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

    pub fn begin(self: *Sqlite) !Txn {
        try self.db.exec("BEGIN", .{}, .{});
        return .{ .store = self, .done = false };
    }

    pub const Txn = struct {
        store: *Sqlite,
        done: bool,

        pub fn commit(self: *Txn) !void {
            try self.store.db.exec("COMMIT", .{}, .{});
            self.done = true;
        }

        pub fn deinit(self: *Txn) void {
            if (!self.done) self.store.db.exec("ROLLBACK", .{}, .{}) catch {};
        }

        pub fn getMeta(self: *Txn) !?core.model.Meta {
            var stmt = try self.store.db.prepare(
                \\SELECT id, replica_id, last_hlc
                \\FROM meta
                \\WHERE id = 1
            );
            defer stmt.deinit();

            const row = try stmt.one(core.model.Meta, .{}, .{});
            return row;
        }

        pub fn insertMeta(self: *Txn, meta: core.model.Meta) !void {
            try self.store.db.exec(
                \\INSERT INTO meta (id, replica_id, last_hlc)
                \\VALUES (?, ?, ?)
            ,
                .{},
                meta,
            );
        }

        pub fn updateMeta(self: *Txn, meta: core.Ts) !void {
            try self.store.db.exec(
                \\UPDATE meta
                \\SET last_hlc = ?
                \\WHERE id = 1
            ,
                .{},
                .{meta.toString()},
            );
        }

        pub fn insertProject(self: *Txn, project: core.model.Project) !void {
            try self.store.db.exec(
                \\INSERT INTO projects (id, name, created_ts, updated_hlc)
                \\VALUES (?, ?, ?, ?)
            ,
                .{},
                .{
                    .id = idBlob(&project.id),
                    .name = project.name,
                    .created_ts = project.created_ts,
                    .updated_hlc = project.updated_hlc,
                },
            );
        }
    };
};

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

    const buf: [16:0]u8 = undefined;
    _ = buf;

    const mode = try db.pragma([16:0]u8, .{}, "journal_mode", "wal");
    if (mode == null or !std.mem.eql(u8, std.mem.sliceTo(&mode.?, 0), "wal")) {
        return error.WalUnavailable;
    }

    _ = try db.pragma([16:0]u8, .{}, "synchronous", "normal");
    _ = try db.pragma(i64, .{}, "foreign_keys", "on");

    return db;
}

const MigrationError = error{ DbNewerThanBinary, MigrationFailed } || sqlite.DynamicStatement.PrepareError;

const migrations = [_]Migration{
    .{ .version = 1, .sql = @embedFile("migrations/0001_init.sql") },
};

const Migration = struct { version: i32, sql: [:0]const u8 };

fn latestVersion() i32 {
    return migrations[migrations.len - 1].version;
}

/// Runs all migrations, up to the latest version.
fn migrate(db: *sqlite.Db) MigrationError!void {
    const current = (try db.pragma(i32, .{}, "user_version", null)) orelse 0;
    if (current > latestVersion()) return error.DbNewerThanBinary;

    inline for (migrations) |m| {
        if (m.version > current) {
            try db.exec("BEGIN IMMEDIATE", .{}, .{});
            errdefer db.exec("ROLLBACK", .{}, .{}) catch |err| {
                std.log.err("failed to run rollback: {}", .{err});
            };

            try execScript(db, m.sql);
            _ = try db.pragma(i32, .{}, "user_version", comptime std.fmt.comptimePrint("{d}", .{m.version}));

            try db.exec("COMMIT", .{}, .{});
        }
    }
}

/// Run a SQL script with sqlite3
/// zig-sqlite3 doesn't have a wrapper for sqlite3_exec
fn execScript(db: *sqlite.Db, sql: [:0]const u8) MigrationError!void {
    var err_msg: [*c]u8 = null;
    const rc = sqlite.c.sqlite3_exec(db.db, sql.ptr, null, null, &err_msg);
    if (rc != sqlite.c.SQLITE_OK) {
        defer if (err_msg != null) sqlite.c.sqlite3_free(err_msg);
        std.log.err("migration failed: {s}", .{err_msg});
        return error.MigrationFailed;
    }
}

// store/sqlite/store.zig (or a small bind.zig next to it)
fn idBlob(id: *const core.Uuid) sqlite.Blob {
    return .{ .data = &id.bytes, .size = id.bytes.len };
}
