const std = @import("std");

pub const ReplicaId = struct {
    value: u64,
    pub fn generate(io: std.Io) ReplicaId {
        const rng_impl: std.Random.IoSource = .{ .io = io };
        const rng = &rng_impl.interface();

        return .{ .value = rng.int(u64) };
    }
};

pub const Uuid = struct {
    bytes: [16]u8,

    pub fn hex(self: Uuid) [32]u8 {
        var buf: [32]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{X}", .{self.bytes}) catch {};
        return buf;
    }
};

pub const V7 = struct {
    mutex: std.Io.Mutex = .{ .state = .init(.unlocked) },
    last_ms: i64 = 0,
    counter: u12 = 0,

    pub fn generate(self: *V7, io: std.Io) std.Io.Cancelable!Uuid {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);

        const rng_impl: std.Random.IoSource = .{ .io = io };
        const rng = &rng_impl.interface();
        const now = std.Io.Timestamp.now(io, .real).toMilliseconds();

        self.advance(now, rng.int(u10)); // Headroom added
        var tail: [8]u8 = undefined;
        rng.bytes(&tail);
        return self.encode(tail);
    }

    fn advance(self: *V7, now: i64, seed: u12) void {
        if (now > self.last_ms) {
            self.last_ms = now;
            self.counter = seed;
        } else if (self.counter == std.math.maxInt(u12)) {
            self.last_ms += 1;
            self.counter = seed;
        } else {
            self.counter += 1;
        }
    }

    fn encode(self: V7, tail: [8]u8) Uuid {
        var u: [16]u8 = undefined;
        std.mem.writeInt(u48, u[0..6], @intCast(self.last_ms), .big);
        u[6] = 0b0111_0000 | @as(u8, @intCast(self.counter >> 8));
        u[7] = @truncate(self.counter);
        @memcpy(u[8..16], &tail);
        u[8] = (u[8] & 0b0011_1111) | 0b1000_0000;
        return .{ .bytes = u };
    }
};

test "V7.advance - same ms increments counter" {
    var v7: V7 = .{ .last_ms = 1000, .counter = 5 };
    v7.advance(1000, 999);
    try std.testing.expectEqual(@as(i64, 1000), v7.last_ms);
    try std.testing.expectEqual(@as(u12, 6), v7.counter);
}

test "V7.advance - counter overflow bumps ms" {
    var v7: V7 = .{ .last_ms = 1000, .counter = 4095 };
    v7.advance(1000, 42);
    try std.testing.expectEqual(@as(i64, 1001), v7.last_ms);
    try std.testing.expectEqual(@as(u12, 42), v7.counter);
}

test "V7.advance - clock regression does not go backward" {
    var v7: V7 = .{ .last_ms = 1000, .counter = 0 };
    v7.advance(100, 42);
    try std.testing.expectEqual(@as(i64, 1000), v7.last_ms);
    try std.testing.expectEqual(@as(u12, 1), v7.counter);
}

test "V7.encode - valid layout" {
    var v7: V7 = .{ .last_ms = 0x0123_4567_89AB, .counter = 0x0ABC };
    const u = v7.encode(.{0xFF} ** 8);
    try std.testing.expectEqualSlices(u8, &.{
        0x01,
        0x23,
        0x45,
        0x67,
        0x89,
        0xAB,
    }, u.bytes[0..6]);
    try std.testing.expectEqual(@as(u8, 0x7A), u.bytes[6]);
    try std.testing.expectEqual(@as(u8, 0xBC), u.bytes[7]);
    try std.testing.expectEqual(@as(u8, 0xBF), u.bytes[8]);
}

test "V7.generate - monotonic across many calls" {
    var v7: V7 = .{};
    var prev = try v7.generate(std.testing.io);
    for (0..10_000) |_| {
        const cur = try v7.generate(std.testing.io);
        try std.testing.expect(std.mem.order(u8, &prev.bytes, &cur.bytes) == .lt);
        prev = cur;
    }
}
