const std = @import("std");
const assert = std.debug.assert;
const executors = @import("../../../main.zig").executors;
const InlineExecutor = executors.@"inline";
const Executor = executors.Executor;
const core = @import("../../../main.zig").core;
const Runnable = core.Runnable;
const future = @import("../main.zig");
const State = future.State;
const model = future.model;
const meta = future.meta;

const Just = @This();
pub const ValueType = void;

pub fn Computation(Continuation: anytype) type {
    return struct {
        next: Continuation,

        pub fn start(self: *@This()) void {
            self.next.@"continue"(
                {},
                .{
                    .executor = InlineExecutor,
                },
            );
        }
    };
}

pub fn materialize(
    _: @This(),
    continuation: anytype,
) Computation(@TypeOf(continuation)) {
    return .{
        .next = continuation,
    };
}

///Future that instantly returns void
pub fn just() Just {
    return .{};
}
