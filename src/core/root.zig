const std = @import("std");

const clock = @import("clock.zig");
pub const Clock = clock.Clock;
pub const Ts = clock.Ts;

const ids = @import("ids.zig");
pub const V7 = ids.V7;
pub const Uuid = ids.Uuid;
pub const ReplicaId = ids.ReplicaId;

const model = @import("model.zig");
pub const Meta = model.Meta;
pub const Workspace = model.Workspace;
pub const Checkout = model.Checkout;

pub const Diagnostic = struct {
    path_buf: [std.fs.max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    detail_buf: [256]u8 = undefined,
    detail_len: usize = 0,
    op: ?[]const u8 = null,
    cause: ?anyerror = null,

    pub fn path(self: *const Diagnostic) ?[]const u8 {
        return if (self.path_len == 0) null else self.path_buf[0..self.path_len];
    }
    pub fn detail(self: *const Diagnostic) ?[]const u8 {
        return if (self.detail_len == 0) null else self.detail_buf[0..self.detail_len];
    }

    pub fn set(
        self: *Diagnostic,
        p: []const u8,
        d: []const u8,
        op: ?[]const u8,
        cause: anyerror,
    ) void {
        self.setPath(p);
        self.setDetail(d);
        self.op = op;
        self.cause = cause;
    }

    pub fn setPath(self: *Diagnostic, p: []const u8) void {
        const n = @min(p.len, self.path_buf.len);
        @memcpy(self.path_buf[0..n], p[0..n]);
        self.path_len = n;
    }

    pub fn setDetail(self: *Diagnostic, d: []const u8) void {
        const n = @min(d.len, self.detail_buf.len);
        @memcpy(self.detail_buf[0..n], d[0..n]);
        self.detail_len = n;
    }
};

test {
    _ = @import("ids.zig");
    _ = @import("clock.zig");
}
