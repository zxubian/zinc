const std = @import("std");
const assert = std.debug.assert;
const executors = @import("../../../root.zig").executors;
const Executor = executors.Executor;
const core = @import("../../../root.zig").core;
const Runnable = core.Runnable;
const future = @import("../root.zig");
const State = future.State;
const meta = future.meta;

pub fn MapOk(MapOkFn: type) type {
    const Args = std.meta.ArgsTuple(MapOkFn);

    return struct {
        map_fn: *const MapOkFn,
        map_ctx: ?*anyopaque,

        pub fn Future(InputFuture: type) type {
            const args_info: std.builtin.Type.Struct = @typeInfo(Args).@"struct";
            const map_fn_has_args = args_info.fields.len > 1;
            // TODO: make this more flexible?
            assert(args_info.fields[0].type == ?*anyopaque);
            if (!map_fn_has_args) {
                @compileError(std.fmt.comptimePrint(
                    "Map function {} in {} with input future {} must accept a parameter",
                    .{
                        MapOkFn,
                        @This(),
                        InputFuture,
                    },
                ));
            }
            const MapOkFnArgType = args_info.fields[1].type;
            const input_future_value_type_info = @typeInfo(InputFuture.ValueType);
            if (std.meta.activeTag(input_future_value_type_info) != .error_union) {
                @compileError(std.fmt.comptimePrint(
                    "Parameter of map function {} in {} with input future {} must be an error-union. Actual type: {}",
                    .{
                        MapOkFn,
                        @This(),
                        InputFuture,
                        InputFuture.ValueType,
                    },
                ));
            }
            const MapOutput = meta.ReturnType(MapOkFn);
            const OutputErrorSet: type = comptime blk: {
                const InputErrorSet = input_future_value_type_info.error_union.error_set;
                break :blk switch (@typeInfo(MapOutput)) {
                    .error_union => |map_output_error_info| map_output_error_info.error_set || InputErrorSet,
                    else => InputErrorSet,
                };
            };
            const OutputPayload: type = switch (@typeInfo(MapOutput)) {
                .error_union => |map_output_error_info| map_output_error_info.payload,
                else => MapOutput,
            };
            const output_value_type: std.builtin.Type = .{
                .error_union = .{
                    .error_set = OutputErrorSet,
                    .payload = OutputPayload,
                },
            };
            const OutputValueType = @Type(output_value_type);
            const UnwrappedValueType = input_future_value_type_info.error_union.payload;
            if (input_future_value_type_info.error_union.payload != MapOkFnArgType) {
                @compileError(std.fmt.comptimePrint(
                    "Incompatible parameter type for map function {} in {} with input future {}. Expected: !{}. Got: !{}",
                    .{
                        MapOkFn,
                        @This(),
                        InputFuture,
                        UnwrappedValueType,
                        MapOkFnArgType,
                    },
                ));
            }
            return struct {
                input_future: InputFuture,
                map_fn: *const MapOkFn,
                map_ctx: ?*anyopaque,

                pub const ValueType = OutputValueType;

                pub fn Computation(Continuation: type) type {
                    return struct {
                        input_computation: InputComputation,
                        map_fn: *const MapOkFn,
                        map_ctx: ?*anyopaque,
                        next: Continuation,

                        const ComputationImpl = @This();
                        const InputComputation = InputFuture.Computation(InputContinuation);

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

                        pub fn run(ctx_: *anyopaque) void {
                            const input_continuation: *InputContinuation = @alignCast(@ptrCast(ctx_));
                            const input_computation: *InputComputation = @fieldParentPtr("next", input_continuation);
                            const self: *ComputationImpl = @fieldParentPtr("input_computation", input_computation);
                            if (std.meta.isError(input_continuation.value)) {
                                self.next.@"continue"(
                                    input_continuation.value,
                                    input_continuation.state,
                                );
                                return;
                            }
                            const input_value = &input_continuation.value;
                            const output: OutputValueType = blk: {
                                if (map_fn_has_args) {
                                    break :blk @call(
                                        .auto,
                                        self.map_fn,
                                        .{
                                            self.map_ctx,
                                            input_value.* catch unreachable,
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

                        pub fn start(self: *@This()) void {
                            self.input_computation.start();
                        }
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

/// This Future applies map_fn to the result of its piped input,
/// but only if the result is not an Error.
/// * Future<V> -> F<map(V)>
///
/// map_fn is executed on the Executor set earlier in the pipeline.
pub fn mapOk(
    map_fn: anytype,
    ctx: ?*anyopaque,
) MapOk(@TypeOf(map_fn)) {
    return .{
        .map_fn = map_fn,
        .map_ctx = ctx,
    };
}
