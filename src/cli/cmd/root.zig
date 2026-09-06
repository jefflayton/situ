const std = @import("std");
const Map = std.static_string_map.StaticStringMap;
const ArgsIter = std.process.Args.Iterator;

const store = @import("store");
const Context = @import("../Context.zig");
const init = @import("init.zig");

pub fn assertCommand(name: []const u8, comptime f: anytype) void {
    const T = @typeInfo(@TypeOf(f)).@"fn";

    if (T.params.len != 2) @compileError(name ++ ": run wants 2 params");
    if (T.params[0].type != *Context) @compileError(name ++ ": first parameter must be *Context");
    if (T.params[1].type != *ArgsIter) @compileError(name ++ ": second parameter must be *ArgsIter");
}

const cmds = .{
    .{ "init", init.run },
};

pub const CommandError = error{
    AlreadyInitialized,
    LinkedCheckout,
} ||
    store.Error ||
    Context.Error;

const Run = *const fn (*Context, *ArgsIter) CommandError!void;
// pub const map: Map(Run) = .initComptime(cmds);

pub const map = blk: {
    var entries: [cmds.len]struct { []const u8, Run } = undefined;
    for (cmds, 0..) |c, i| {
        assertCommand(c[0], c[1]);
        entries[i] = .{ c[0], c[1] };
    }
    break :blk Map(Run).initComptime(entries);
};
