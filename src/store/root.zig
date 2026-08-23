pub const Sqlite = @import("sqlite/store.zig").Sqlite;
pub const Txn = @import("sqlite/store.zig").Txn;

pub fn assertStore(comptime T: type) void {
    const P = switch (@typeInfo(T)) {
        .pointer => |p| p.child,
        else => T,
    };

    if (!@hasDecl(P, "Txn")) {
        @compileError(@typeName(P) ++ ": missing Txn");
    }
    comptime assertTxn(P.Txn);
}

pub fn assertTxn(comptime T: type) void {
    const P = switch (@typeInfo(T)) {
        .pointer => |p| p.child,
        else => T,
    };

    comptime checkDecl(P, "commit");
    const commit = @typeInfo(@TypeOf(P.commit)).@"fn";
    if (commit.params.len != 1) {
        @compileError(@typeName(P) ++ ": commit invalid params");
    }

    comptime checkDecl(P, "deinit");
    const deinit = @typeInfo(@TypeOf(P.commit)).@"fn";
    if (deinit.params.len != 1) {
        @compileError(@typeName(P) ++ ": deinit invalid params");
    }

    comptime checkDecl(P, "insertProject");
    const insertProject = @typeInfo(@TypeOf(P.insertProject)).@"fn";
    if (insertProject.params.len != 2) {
        @compileError(@typeName(P) ++ ": insertProject invalid params");
    }
}

fn checkDecl(comptime T: type, decl: []const u8) void {
    if (!@hasDecl(T, decl)) {
        @compileError(@typeName(T) ++ ": missing " ++ decl);
    }
}
