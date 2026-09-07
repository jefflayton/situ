const std = @import("std");
const Map = std.static_string_map.StaticStringMap;
const ArgsIter = std.process.Args.Iterator;

const store = @import("store");
const Context = @import("../Context.zig");

pub const CommandError = error{ AlreadyInitialized, LinkedCheckout } ||
    store.Error ||
    Context.Error;

pub const mods = .{ .init = @import("init.zig") };

pub const Command = blk: {
    const names = std.meta.fieldNames(@TypeOf(mods));
    var values: [names.len]u8 = undefined;
    for (names, 0..) |n, i| {
        assertCommand(n, @field(mods, n));
        values[i] = i;
    }
    const v = values;
    break :blk @Enum(u8, .exhaustive, names, &v);
};

const CommandUnion = blk: {
    const names = std.meta.fieldNames(@TypeOf(mods));
    var values: [names.len]type = undefined;
    var attrs: [names.len]std.builtin.Type.UnionField.Attributes = undefined;
    for (names, 0..) |n, i| {
        values[i] = @field(mods, n).Opts;
        attrs[i] = .{ .@"align" = @alignOf(@field(mods, n).Opts) };
    }
    const v = values;
    const a = attrs;
    break :blk @Union(.auto, Command, names, &v, &a);
};

/// The list of options available on root call
pub const Root = struct {
    version: bool = false,
    pub const short = .{ .version = 'v' };
};

/// The list of options available to all commands
pub const Global = struct {
    help: bool = false,
    pub const short = .{ .help = 'h' };
};

/// The parsed arguments
pub const Parsed = union(enum) {
    version,
    help: ?Command,
    command: CommandUnion,
};

pub fn dispatch(ctx: *Context, parsed: Parsed) CommandError!void {
    switch (parsed.command) {
        inline else => |*opts, tag| try @field(mods, @tagName(tag)).run(ctx, opts),
    }
}

pub fn assertCommand(name: []const u8, comptime cmd: type) void {
    if (!@hasDecl(cmd, "Opts")) @compileError(name ++ ": missing pub const Opts");
    if (!@hasDecl(cmd, "run")) @compileError(name ++ ": missing pub fn run");
    if (!@hasDecl(cmd, "about")) @compileError(name ++ ": missing pub const about");

    const T = @typeInfo(@TypeOf(cmd.run)).@"fn";
    if (T.params.len != 2) @compileError(name ++ ": run wants 2 params");
    if (T.params[0].type != *Context) @compileError(name ++ ": param 0 must be *Context");
    if (T.params[1].type != *const cmd.Opts) @compileError(name ++ ": param 1 must be *const " ++ name ++ ".Opts");
    if (T.return_type != CommandError!void) @compileError(name ++ ": must return CommandError!void");

    if (@typeInfo(cmd.Opts) != .@"struct") @compileError(name ++ ": Opts must be a struct");
    for (@typeInfo(cmd.Opts).@"struct".fields) |of| {
        if (of.default_value_ptr == null)
            @compileError(name ++ ".Opts." ++ of.name ++ ": needs a default");
    }
}
