const std = @import("std");

const clock = @import("clock.zig");
pub const Clock = clock.Clock;
pub const Ts = clock.Ts;
const ids = @import("ids.zig");
pub const V7 = ids.V7;
pub const Uuid = ids.Uuid;
pub const ReplicaId = ids.ReplicaId;
pub const model = @import("model.zig");

pub const Diagnostic = struct {
    path_buf: [std.fs.max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    detail_buf: [256]u8 = undefined,
    detail_len: usize = 0,
    op: ?[]const u8 = null,
    cause: ?anyerror = null,

    pub fn path(d: *const Diagnostic) ?[]const u8 {
        return if (d.path_len == 0) null else d.path_buf[0..d.path_len];
    }

    pub fn set(
        d: *Diagnostic,
        p: []const u8,
        detail: []const u8,
        op: ?[]const u8,
        cause: anyerror,
    ) void {
        d.setPath(p);
        d.setDetail(detail);
        d.op = op;
        d.cause = cause;
    }

    pub fn setPath(d: *Diagnostic, p: []const u8) void {
        const n = @min(p.len, d.path_buf.len);
        @memcpy(d.path_buf[0..n], p[0..n]);
        d.path_len = n;
    }

    pub fn setDetail(d: *Diagnostic, detail: []const u8) void {
        const n = @min(detail.len, d.path_buf.len);
        @memcpy(d.detail_buf[0..n], detail[0..n]);
        d.detail_len = n;
    }
};

test {
    _ = @import("ids.zig");
    _ = @import("clock.zig");
}
