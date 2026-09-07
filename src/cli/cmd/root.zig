const std = @import("std");
const Map = std.static_string_map.StaticStringMap;
const ArgsIter = std.process.Args.Iterator;

const store = @import("store");

const Context = @import("../Context.zig");
const help = @import("../help.zig");

pub const CommandError = error{ AlreadyInitialized, LinkedCheckout } ||
    store.Error ||
    Context.Error ||
    std.Io.Writer.Error;

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
    help: bool = false,
    version: bool = false,

    pub const flags = .{
        .help = .{ .short = 'h', .about = "Print help" },
        .version = .{ .about = "Print version" },
    };

    pub const about: []const u8 = "Situ - Your notes, in place.";
    pub const usage: []const u8 = "[OPTIONS] <COMMAND>";
};

// /// The list of options available to all commands
pub const Global = struct {};

/// The parsed arguments
pub const Parsed = union(enum) {
    root: Root,
    command: CommandUnion,
};

/// Dispatches a command, calling it's help or run commands
pub fn dispatch(ctx: *Context, parsed: Parsed) CommandError!void {
    switch (parsed.command) {
        inline else => |*opts, tag| {
            if (@hasField(@TypeOf(opts.*), "help") and opts.help)
                return help.print(ctx, tag);
            try @field(mods, @tagName(tag)).run(ctx, opts);
        },
    }
}

/// Finds and returns the short form of a field, if one exists
pub fn shortOf(comptime T: type, comptime field: []const u8) ?u8 {
    if (!@hasField(@TypeOf(T.flags), field)) return null;
    if (!@hasField(@TypeOf(@field(T.flags, field)), "short")) return null;
    return @field(T.flags, field).short;
}

/// Asserts the provided command has all of the required properties.
pub fn assertCommand(name: []const u8, comptime cmd: type) void {
    if (!@hasDecl(cmd, "Opts")) @compileError(name ++ ": missing pub const Opts");
    if (!@hasDecl(cmd, "run")) @compileError(name ++ ": missing pub fn run");

    // run
    const T = @typeInfo(@TypeOf(cmd.run)).@"fn";
    if (T.params.len != 2) @compileError(name ++ ": run wants 2 params");
    if (T.params[0].type != *Context) @compileError(name ++ ": param 0 must be *Context");
    if (T.params[1].type != *const cmd.Opts)
        @compileError(name ++ ": param 1 must be *const " ++ name ++ ".Opts");
    if (T.return_type != CommandError!void)
        @compileError(name ++ ": must return CommandError!void");

    // Opts
    assertOpts(cmd.Opts);
}

/// Assers the provided Opts type has all of the required properties.
pub fn assertOpts(comptime T: type) void {
    const name = @typeName(T);
    if (@typeInfo(T) != .@"struct") @compileError(name ++ ": must be a struct");

    // Opts.flags
    if (!@hasDecl(T, "flags"))
        @compileError(name ++ ": must be contain declaration flags");

    if (@typeInfo(@TypeOf(T.flags)) != .@"struct")
        @compileError(name ++ ".flags: must be a struct");

    // Opts fields
    inline for (@typeInfo(T).@"struct".fields) |of| {
        if (of.default_value_ptr == null)
            @compileError(name ++ "." ++ of.name ++ ": needs a default");
        if (!@hasField(@TypeOf(T.flags), of.name))
            @compileError(name ++ ".flags: must contain field for " ++ of.name);
        if (!@hasField(@TypeOf(@field(T.flags, of.name)), "about"))
            @compileError(name ++ ".flags." ++ of.name ++ ": must contain about field");
        if (@hasDecl(@TypeOf(@field(T.flags, of.name)), "short")) {
            if (!@typeInfo(@field(T.flags, of.name).short) != u8)
                @compileError(name ++ ".flags." ++ of.name ++ ".short: must be u8");
        }
    }

    // about
    if (!@hasDecl(T, "about"))
        @compileError(name ++ ": missing pub const about");
    if (@TypeOf(T.about) != []const u8)
        @compileError(name ++ ".about: must be []u8. found " ++ @typeName(@TypeOf(T.about)));
    // usage
    if (!@hasDecl(T, "usage"))
        @compileError(name ++ ": missing pub const usage");
    if (@TypeOf(T.usage) != []const u8)
        @compileError(name ++ ".usage: must be []u8. found " ++ @typeName(@TypeOf(T.usage)));
}
