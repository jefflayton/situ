const std = @import("std");

pub const Uuid = struct {
    bytes: [16]u8,
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

        self.advance(now, rng.int(u10));
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

    fn encode(self: *V7, tail: [8]u8) Uuid {
        var u: [16]u8 = undefined;
        std.mem.writeInt(u48, u[0..6], @intCast(self.last_ms), .big);
        u[6] = 0b111_0000 | @as(u8, @intCast(self.counter >> 8));
        u[7] = @truncate(self.counter);
        @memcpy(u[8..16], &tail);
        u[8] = (u[8] & 0b0011_1111) | 0b10_000000;
        return .{ .bytes = u };
    }
};

pub const ReplicaId = struct {
    value: u64,
    pub fn generate(io: std.Io) ReplicaId {
        const rng_impl: std.Random.IoSource = .{ .io = io };
        const rng = &rng_impl.interface();

        return .{ .value = rng.int(u64) };
    }
};
test {
    var v7: V7 = .{};
    const u = try v7.generate(std.testing.io);
    try std.testing.expectEqual(@as(u8, 0x70), u.bytes[6] & 0xF0);
}
