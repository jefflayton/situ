const std = @import("std");

pub const Ts = struct {
    wall: u64,
    counter: u16 = 0,

    /// Returns the HLC timestamp as hex string in the format:
    /// <wall>-<counter>
    /// Ex:
    ///     Input:  Ts{ .wall = 1000, .counter = 5 }
    ///     Output: 00000000000003E8-0005
    pub fn toString(self: Ts) [21]u8 {
        var buf: [21]u8 = undefined;
        _ = std.fmt.bufPrint(
            &buf,
            "{X:0>16}-{X:0>4}",
            .{ self.wall, self.counter },
        ) catch {};
        return buf;
    }

    pub const ParseError = error{InvalidTs} || std.fmt.ParseIntError;
    /// Parse the HLC string into a Ts.
    pub fn parse(s: []const u8) ParseError!Ts {
        if (s.len != 21 or s[16] != '-') return ParseError.InvalidTs;
        return .{
            .wall = try std.fmt.parseInt(u64, s[0..16], 16),
            .counter = try std.fmt.parseInt(u16, s[17..21], 16),
        };
    }
};

pub const ClockError = error{CounterOverflow} || std.Io.Cancelable;
pub const Clock = struct {
    mutex: std.Io.Mutex = .{ .state = .init(.unlocked) },
    last: Ts = .{ .wall = 0 },

    /// Initialize Clock fron existing meta.last_hlc.
    pub fn initFrom(stored: Ts) Clock {
        return .{ .last = stored };
    }

    /// Returns the next HLC timestamp for the current wall clock time.
    pub fn now(self: *Clock, io: std.Io) ClockError!Ts {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        return self.advance(std.Io.Timestamp.now(io, .real).toMilliseconds());
    }

    /// Given a wall_now and the last Ts, retuns the next HLC timestamp.
    fn advance(self: *Clock, wall_now: i64) ClockError!Ts {
        var ts: Ts = .{ .wall = @max(self.last.wall, wall_now) };
        if (wall_now > self.last.wall) {
            self.last = ts;
            return ts;
        }

        const ov = @addWithOverflow(self.last.counter, 1);
        if (ov[1] != 0) {
            return ClockError.CounterOverflow;
        } else {
            ts.counter = ov[0];
        }
        self.last = ts;
        return ts;
    }
};

test "Ts.toString" {
    var ts: Ts = .{ .wall = 1000, .counter = 5 };
    try std.testing.expectEqualStrings("00000000000003E8-0005", &ts.toString());
}

test "Ts.toString - zero clock" {
    var ts: Ts = .{ .wall = 0 };
    try std.testing.expectEqualStrings("0000000000000000-0000", &ts.toString());
}

test "Ts.parse" {
    const s: []const u8 = "00000000000003E8-0005";
    const ts = try Ts.parse(s);
    try std.testing.expectEqual(1000, ts.wall);
    try std.testing.expectEqual(5, ts.counter);
}

test "Clock.advance - last.wall > now" {
    var c = Clock{ .last = .{ .wall = 100, .counter = 0 } };
    const ts = try c.advance(95);

    try std.testing.expectEqual(100, ts.wall);
    try std.testing.expectEqual(1, ts.counter);
}

test "Clock.advance - last.wall = now" {
    var c = Clock{ .last = .{ .wall = 100, .counter = 0 } };
    const ts = try c.advance(100);

    try std.testing.expectEqual(100, ts.wall);
    try std.testing.expectEqual(1, ts.counter);
}

test "Clock.advance - last.wall < now" {
    var c = Clock{ .last = .{ .wall = 100, .counter = 0 } };
    const ts = try c.advance(105);

    try std.testing.expectEqual(105, ts.wall);
    try std.testing.expectEqual(0, ts.counter);
}

test "Clock.advance - monotonic under a frozen clock" {
    var c = Clock{ .last = .{ .wall = 100, .counter = 0 } };
    var prev = try c.advance(100);

    for (0..5) |_| {
        const ts = try c.advance(100);
        try std.testing.expect(ts.wall > prev.wall or
            (ts.wall == prev.wall and ts.counter > prev.counter));
        prev = ts;
    }
}

test "Clock.advance - overflow error" {
    var c = Clock{ .last = .{ .wall = 100, .counter = 65535 } };
    const ts = c.advance(100);

    try std.testing.expectError(ClockError.CounterOverflow, ts);
}
