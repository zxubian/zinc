const std = @import("std");
const assert = std.debug.assert;
const executors = @import("../../../main.zig").executors;
const Executor = executors.Executor;
const core = @import("../../../main.zig").core;
const Runnable = core.Runnable;
const future = @import("../main.zig");
const State = future.State;
const model = future.model;
const meta = future.meta;

const Via = @This();

next_executor: Executor,

pub fn Future(InputFuture: type) type {
    return struct {
        input_future: InputFuture,
        next_executor: Executor,

        pub const ValueType = InputFuture.ValueType;

        pub const ContinuationForInputFuture = struct {
            value: InputFuture.ValueType = undefined,
            pub fn @"continue"(
                self: *@This(),
                value: InputFuture.ValueType,
                _: State,
            ) void {
                self.value = value;
            }
        };

        pub fn Computation(Continuation: anytype) type {
            return struct {
                input_computation: InputFuture.Computation(ContinuationForInputFuture),
                next_executor: Executor,
                next: Continuation,

                pub fn start(self: *@This()) void {
                    self.input_computation.start();
                    const input_value: *InputFuture.ValueType = &self.input_computation.next.value;
                    self.next.@"continue"(
                        input_value.*,
                        State{
                            .executor = self.next_executor,
                        },
                    );
                }
            };
        }

        pub fn materialize(
            self: @This(),
            continuation: anytype,
        ) Computation(@TypeOf(continuation)) {
            const input_computation = self.input_future.materialize(ContinuationForInputFuture{});
            return .{
                .input_computation = input_computation,
                .next_executor = self.next_executor,
                .next = continuation,
            };
        }
    };
}

/// F<V> -> F<V>
pub fn pipe(
    self: *const Via,
    f: anytype,
) Future(@TypeOf(f)) {
    return .{
        .input_future = f,
        .next_executor = self.next_executor,
    };
}

///Make the Future following Via to be executed on `executor`
pub fn via(executor: Executor) Via {
    return .{
        .next_executor = executor,
    };
}
