const std = @import("std");
const assert = std.debug.assert;
const executors = @import("../../../main.zig").executors;
const Executor = executors.Executor;
const core = @import("../../../main.zig").core;
const Runnable = core.Runnable;
const future = @import("../main.zig");
const State = future.State;
const model = future.model;
const Computation = model.Computation;
const meta = future.meta;
const f = future.Impl;

fn SubmitFuture(MapFn: type) type {
    return future.syntax.pipeline.Result(std.meta.Tuple(&[_]type{
        future.make.just,
        future.combinators.via,
        future.combinators.map.Map(MapFn),
    }));
}

pub inline fn submit(
    executor: Executor,
    lambda: anytype,
    ctx: ?*anyopaque,
) SubmitFuture(@TypeOf(lambda)) {
    return f.pipeline(.{
        f.just(),
        f.via(executor),
        f.map(lambda, ctx),
    });
}
