const std = @import("std");
const assert = std.debug.assert;
const executors = @import("../../../root.zig").executors;
const Executor = executors.Executor;
const core = @import("../../../root.zig").core;
const Runnable = core.Runnable;
const future = @import("../root.zig");
const State = future.State;
const model = future.model;
const meta = future.meta;

pub fn Map(MapFn: type) type {
    const Args = std.meta.ArgsTuple(MapFn);
    const OutputValueType = meta.ReturnType(MapFn);

    return struct {
        map_fn: *const MapFn,
        map_ctx: ?*anyopaque,

        pub fn Future(InputFuture: type) type {
            const args_info: std.builtin.Type.Struct = @typeInfo(Args).@"struct";
            const map_fn_has_args = args_info.fields.len > 1;
            // TODO: make this more flexible?
            assert(args_info.fields[0].type == ?*anyopaque);
            if (map_fn_has_args) {
                const MapFnArgType = args_info.fields[1].type;
                if (InputFuture.ValueType != MapFnArgType) {
                    @compileError(std.fmt.comptimePrint(
                        "Incorrect parameter type for map function {} in {} with input future {}. Expected: {}. Got: {}",
                        .{
                            MapFn,
                            @This(),
                            InputFuture,
                            InputFuture.ValueType,
                            MapFnArgType,
                        },
                    ));
                }
            }
            return struct {
                input_future: InputFuture,
                map_fn: *const MapFn,
                map_ctx: ?*anyopaque,

                pub const ValueType = OutputValueType;

                pub fn Computation(Continuation: type) type {
                    return struct {
                        input_computation: InputComputation,
                        map_fn: *const MapFn,
                        map_ctx: ?*anyopaque,
                        runnable: Runnable = undefined,
                        next: Continuation,

                        const Impl = @This();
                        const InputComputation = InputFuture.Computation(InputContinuation);

                        pub fn start(self: *Impl) void {
                            self.input_computation.start();
                        }

                        pub fn run(ctx_: *anyopaque) void {
                            const input_continuation: *InputContinuation = @alignCast(@ptrCast(ctx_));
                            const input_computation: *InputComputation = @fieldParentPtr("next", input_continuation);
                            const self: *Impl = @fieldParentPtr("input_computation", input_computation);
                            const input_value = &input_continuation.value;
                            const output: OutputValueType = blk: {
                                if (map_fn_has_args) {
                                    break :blk @call(
                                        .auto,
                                        self.map_fn,
                                        .{
                                            self.map_ctx,
                                            input_value.*,
                                        },
                                    );
                                } else {
                                    break :blk @call(
                                        .auto,
                                        self.map_fn,
                                        .{self.map_ctx},
                                    );
                                }
                            };
                            self.next.@"continue"(
                                output,
                                input_continuation.state,
                            );
                        }

                        pub const InputContinuation = struct {
                            value: InputFuture.ValueType = undefined,
                            state: State = undefined,
                            runnable: Runnable = undefined,

                            pub fn @"continue"(
                                self: *@This(),
                                value: InputFuture.ValueType,
                                state: State,
                            ) void {
                                self.value = value;
                                self.state = state;
                                self.runnable = .{
                                    .runFn = run,
                                    .ptr = self,
                                };
                                state.executor.submitRunnable(&self.runnable);
                            }
                        };
                    };
                }

                pub fn materialize(
                    self: @This(),
                    continuation: anytype,
                ) Computation(@TypeOf(continuation)) {
                    const Result = Computation(@TypeOf(continuation));
                    const InputContinuation = Result.InputContinuation;
                    return .{
                        .input_computation = self.input_future.materialize(
                            InputContinuation{},
                        ),

                        .map_fn = self.map_fn,
                        .map_ctx = self.map_ctx,
                        .next = continuation,
                    };
                }

                pub fn awaitable(self: @This()) future.Impl.Awaitable(@This()) {
                    return .{
                        .future = self,
                    };
                }
            };
        }

        /// F<V> -> F<map(V)>
        pub fn pipe(
            self: @This(),
            f: anytype,
        ) Future(@TypeOf(f)) {
            return .{
                .input_future = f,
                .map_fn = self.map_fn,
                .map_ctx = self.map_ctx,
            };
        }
    };
}

/// This Future applies map_fn to the result of its piped input.
/// * Future<T> -> Future<map_fn(T)>
///
/// `map_fn` is executed on the Executor set earlier in the pipeline.
pub fn map(
    map_fn: anytype,
    ctx: ?*anyopaque,
) Map(@TypeOf(map_fn)) {
    return .{
        .map_fn = map_fn,
        .map_ctx = ctx,
    };
}
