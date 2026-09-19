const std = @import("std");

const core = @import("core");
const store = @import("store");

const logic = @import("root.zig");

pub fn create(txn: anytype, _: *logic.Context, args: anytype) store.Error!void {
    comptime store.assertTxn(@TypeOf(txn));

    const c: core.Checkout = .{
        .workspace_id = args.workspace_id,
        .path = args.path,
    };
    try txn.insertCheckout(c);
}
