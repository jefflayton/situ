const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ.Map;
const ArrayList = std.array_list.Managed;

const core = @import("core");
const logic = @import("logic");
const store = @import("store");

const args_mod = @import("args.zig");
const cmd = @import("cmd/root.zig");
const Config = @import("Config.zig");
const Context = @import("Context.zig");
const paths = @import("paths.zig");
const WorkspaceConfig = @import("WorkspaceConfig.zig");
const help = @import("help.zig");

const BUF_SIZE = 256;
pub fn main(init: std.process.Init) u8 {
    var context: Context = .{
        .io = init.io,
        .gpa = init.gpa,
        .environ = init.environ_map,
    };
    var args = init.minimal.args.iterate();

    const parsed = args_mod.parse(&args) catch {
        // TODO: Output Usage to STDERR
        return 2;
    };

    switch (parsed) {
        .version => {
            // TODO: Output version
            return 0;
        },
        .help => |c| {
            help.print(&context, c);
            return 0;
        },
        .command => cmd.dispatch(&context, parsed) catch |err| {
            reportError(err, &context.diag);
            return 1;
        },
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
    _ = @import("args.zig");
    _ = @import("paths.zig");
    _ = @import("WorkspaceConfig.zig");
}
