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

const STACK_LEN: usize = 8;
pub const Diagnostic = struct {
    pub const Info = struct {
        op: ?[]const u8 = null,
        context: [256]u8 = undefined,
        context_len: usize = 0,
        err: anyerror = undefined,

        /// Copy the context into info
        pub fn setContext(self: *Info, c: []const u8) void {
            const n = @min(c.len, self.context.len);
            @memcpy(self.context[0..n], c[0..n]);
            self.context_len = n;
        }
    };

    stack: [STACK_LEN]?Info = .{null} ** STACK_LEN,
    idx: usize = 0,

    const PartialInfo = struct { op: ?[]const u8 = null, context: ?[]const u8 = null };

    /// Add a new entry to the diagnistic stack
    pub fn fail(self: *Diagnostic, err: anytype, info: PartialInfo) void {
        if (self.idx == STACK_LEN) self.dropOldestFromStack();

        self.stack[self.idx] = .{
            .err = err,
            .op = info.op,
        };
        if (info.context) |c| self.stack[self.idx].?.setContext(c);
        self.idx += 1;
    }

    /// Calls `fail()`, then returns `err`.
    pub fn failAs(self: *Diagnostic, err: anytype, info: PartialInfo) @TypeOf(err) {
        self.fail(err, info);
        return err;
    }

    fn dropOldestFromStack(self: *Diagnostic) void {
        var i: usize = 1;
        while (i < STACK_LEN) : (i += 1) {
            self.stack[i - 1] = self.stack[i];
        }
        self.idx -= 1;
    }

    /// Formats the Diagnostic for a Writer.
    ///
    /// Example:
    /// error: MyError - MyOp (context)
    ///   while: AnotherError - AnotherOp (more context)
    ///   while: ThirdError - ThirdOp (even more context)
    pub fn format(self: *Diagnostic, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var i = self.idx;
        while (i > 0) {
            i -= 1;
            const s = self.stack[i] orelse continue;
            try w.print("{s}: {t}", .{
                if (i == self.idx - 1) "error" else "  while",
                s.err,
            });
            if (s.op) |o| try w.print(" - {s}", .{o});
            if (s.context_len > 0) {
                try w.print(" ({s})", .{s.context[0..s.context_len]});
            }
            try w.print("\n", .{});
        }
    }
};

test {
    _ = @import("ids.zig");
    _ = @import("clock.zig");
}

fn failsWithMyErr(d: *Diagnostic) error{MyErr}!u32 {
    return d.failAs(error.MyErr, .{ .op = "myFunc" });
}

fn expectFormat(d: *Diagnostic, expected: []const u8) !void {
    var buf: [1028]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try d.format(&w);

    try std.testing.expectEqualStrings(expected, w.buffered());
}

test "Diagnostic - 0 errors" {
    var d: Diagnostic = .{};

    try expectFormat(&d, "");
}

test "Diagnostic - 1 error" {
    var d: Diagnostic = .{};

    try std.testing.expectError(
        error.MyErr,
        failsWithMyErr(&d),
    );

    try expectFormat(
        &d,
        \\error: MyErr - myFunc
        \\
        ,
    );
}

test "Diagnostic - STACK_LEN + {diff} errors" {
    var d: Diagnostic = .{};

    const diff = 2;
    for (1..STACK_LEN + diff + 1) |i| {
        var buf: [2]u8 = undefined;
        const b = try std.fmt.bufPrint(&buf, "{d}", .{i});
        d.fail(error.MyErr, .{ .op = "myFunc", .context = b });
    }

    try expectFormat(
        &d,
        \\error: MyErr - myFunc (10)
        \\  while: MyErr - myFunc (9)
        \\  while: MyErr - myFunc (8)
        \\  while: MyErr - myFunc (7)
        \\  while: MyErr - myFunc (6)
        \\  while: MyErr - myFunc (5)
        \\  while: MyErr - myFunc (4)
        \\  while: MyErr - myFunc (3)
        \\
        ,
    );

    try std.testing.expectEqual(STACK_LEN, d.idx);

    var buf_head: [2]u8 = undefined;
    const b_head = try std.fmt.bufPrint(&buf_head, "{d}", .{diff + 1});
    const head = d.stack[0].?;
    try std.testing.expectEqualStrings(b_head, head.context[0..head.context_len]);

    var buf_tail: [2]u8 = undefined;
    const b_tail = try std.fmt.bufPrint(&buf_tail, "{d}", .{STACK_LEN + diff});
    const tail = d.stack[d.idx - 1].?;
    try std.testing.expectEqualStrings(b_tail, tail.context[0..tail.context_len]);
}

test "Diagnostic - null op" {
    var d: Diagnostic = .{};

    d.fail(error.MyErr, .{});

    try expectFormat(&d, "error: MyErr\n");
}

test "Diagnostic - Writer Error" {
    var d: Diagnostic = .{};

    d.fail(error.MyErr, .{ .op = "myFunc", .context = "doing stuff" });

    var buf: [4]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try std.testing.expectError(std.Io.Writer.Error.WriteFailed, d.format(&w));
}
