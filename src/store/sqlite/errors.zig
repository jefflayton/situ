const std = @import("std");

const core = @import("core");
const sqlite = @import("sqlite");
const c = sqlite.c;

const Error = @import("../root.zig").Error;

pub fn classifyCode(rc: c_int) Error {
    return switch (rc) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.Busy,
        c.SQLITE_CONSTRAINT => error.Conflict,
        c.SQLITE_CORRUPT, c.SQLITE_NOTADB => error.Corrupt,
        c.SQLITE_NOMEM => error.OutOfMemory,
        else => error.Migration,
    };
}

pub fn classify(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.SQLiteBusy, error.SQLiteLocked => error.Busy,
        error.SQLiteConstraint, error.SQLiteConstraintUnique, error.SQLiteConstraintPrimaryKey => error.Conflict,
        error.SQLiteCorrupt, error.SQLiteNotADatabase => error.Corrupt,
        else => error.Io,
    };
}

pub fn capture(db: *sqlite.Db, err: anyerror, op: []const u8, diag: ?*core.Diagnostic) Error {
    if (diag) |d| {
        d.fail(err, .{ .op = op, .context = std.mem.span(sqlite.c.sqlite3_errmsg(db.db)) });
    }
    return classify(err);
}
