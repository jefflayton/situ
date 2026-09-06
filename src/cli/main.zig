const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ.Map;
const ArrayList = std.array_list.Managed;

const core = @import("core");
const logic = @import("logic");
const store = @import("store");

const run = @import("cmd/init.zig").run;
const cmd_map = @import("cmd/root.zig").map;
const Config = @import("Config.zig");
const Context = @import("Context.zig");
const paths = @import("paths.zig");
const WorkspaceConfig = @import("WorkspaceConfig.zig");

const BUF_SIZE = 256;
pub fn main(init: std.process.Init) u8 {
    var context: Context = .{
        .io = init.io,
        .gpa = init.gpa,
        .environ = init.environ_map,
    };

    var args = init.minimal.args.iterate();

    const cmd = cmd_map.get("init");
    if (cmd) |c| {
        c(&context, &args) catch |err| {
            reportError(err, &context.diag);
            return 1;
        };
    } else {
        std.log.err("error: unknown command {s}", .{"UNIMPLEMENTED"});
    }
    return 0;
}

fn reportError(err: anyerror, d: *const core.Diagnostic) void {
    switch (err) {
        error.AlreadyInitialized => std.log.err("already a situ workspace", .{}),
        error.OutOfMemory => std.log.err("out of memory", .{}),
        else => if (d.path()) |p|
            std.log.err("{s}: {s}: {t}", .{ p, d.op orelse "?", err })
        else
            std.log.err("{t}", .{err}),
    }
}

test {
    _ = @import("paths.zig");
    _ = @import("WorkspaceConfig.zig");
}
