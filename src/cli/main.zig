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
const help = @import("help.zig");
const paths = @import("paths.zig");
const WorkspaceConfig = @import("WorkspaceConfig.zig");

const log = std.log.scoped(.cli);

const BUF_SIZE = 256;
const ERR_BUF_SIZE = 1024;
pub fn main(init: std.process.Init) u8 {
    var stdin_buf: [BUF_SIZE]u8 = undefined;
    var stdin_file = std.Io.File.stdin();
    var stdin_reader = stdin_file.reader(init.io, &stdin_buf);
    const stdin = &stdin_reader.interface;

    var stdout_buf: [BUF_SIZE]u8 = undefined;
    var stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    var stderr_buf: [ERR_BUF_SIZE]u8 = undefined;
    var stderr_file = std.Io.File.stderr();
    var stderr_writer = stderr_file.writer(init.io, &stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    var ctx: Context = .{
        .io = init.io,
        .gpa = init.gpa,
        .environ = init.environ_map,
        .stdin = stdin,
        .stdout = stdout,
        .stderr = stderr,
    };
    var args = init.minimal.args.iterate();

    const parsed = args_mod.parse(&args) catch {
        help.usage(&ctx, null) catch |err| {
            reportError(err, &ctx.diag);
            return 1;
        };
        return 2;
    };

    switch (parsed) {
        .root => |r| {
            if (r.help)
                help.print(&ctx, null) catch |err| {
                    reportError(err, &ctx.diag);
                    return 1;
                }
            else if (r.version)
                std.log.info("1.0", .{});
        },
        .command => cmd.dispatch(&ctx, parsed) catch |err| {
            reportError(err, &ctx.diag);
            return 1;
        },
    }
    return 0;
}

fn reportError(err: anyerror, d: *const core.Diagnostic) void {
    switch (err) {
        error.AlreadyInitialized => log.err("already a situ workspace", .{}),
        error.OutOfMemory => log.err("out of memory", .{}),
        else => {
            log.err("{s} - {s}: {s}: {t}\ncause: {t}", .{
                d.path() orelse "",
                d.detail() orelse "",
                d.op orelse "?",
                err,
                d.cause orelse err,
            });
        },
    }

    if (@import("builtin").mode == .Debug) {
        if (@errorReturnTrace()) |t| log.err("{any}", .{t});
    }
}

test {
    _ = @import("args.zig");
    _ = @import("paths.zig");
    _ = @import("WorkspaceConfig.zig");
}
