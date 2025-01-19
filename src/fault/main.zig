const std = @import("std");

pub const BuildVariant = enum {
    none,
    thread,
    fiber,
};

pub const stdlike = @import("./stdlike/main.zig");

const fault_injection_builtin = @import("zig_async_fault_injection");
const Injector = @import("./injector.zig");

var injector: Injector = if (fault_injection_builtin.build_variant == .none)
{} else .{};

pub fn injectFault() void {
    injector.maybeInjectFault();
}
