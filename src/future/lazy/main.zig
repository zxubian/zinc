const std = @import("std");
const assert = std.debug.assert;
const executors = @import("../../main.zig").executors;
const Executor = executors.Executor;
const core = @import("../../main.zig").core;
const Runnable = core.Runnable;

/// --- external re-exports ---
pub const Impl = struct {
    // --- generators ---
    pub const submit = make.submit.submit;
    pub const just = make.just.just;
    pub const constValue = make.constValue.constValue;
    pub const Value = make.value.Value;
    pub const value = make.value.value;
    // --- combinators ---
    pub const via = combinators.via.via;
    pub const map = combinators.map.map;
    pub const mapOk = combinators.mapOk.mapOk;
    pub const andThen = combinators.andThen.andThen;
    pub const orElse = combinators.orElse.orElse;
    // --- terminators ---
    pub const get = terminators.get;
    // --- syntax ---
    pub const pipeline = syntax.pipeline.pipeline;
};

// --- internal implementation ---
pub const meta = @import("./meta.zig");
pub const make = @import("./make/main.zig");
pub const terminators = @import("./terminators//main.zig");
pub const combinators = @import("./combinators/main.zig");
pub const syntax = @import("./syntax/main.zig");

pub const State = struct {
    executor: Executor,
};

test {
    _ = @import("./tests.zig");
}
