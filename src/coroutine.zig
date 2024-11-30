//! Stackfull coroutine
const std = @import("std");
const log = std.log.scoped(.coroutine);
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Runnable = @import("./runnable.zig");
const Closure = @import("./closure.zig");
const ExecutionContext = @import("./coroutine/executionContext.zig");
const Trampoline = ExecutionContext.Trampoline;

pub const Stack = ExecutionContext.Stack;

const Coroutine = @This();

routine: *Runnable = undefined,
previous_context: ExecutionContext = undefined,
stack: Stack = undefined,
execution_context: ExecutionContext = undefined,
is_completed: bool = false,

pub fn init(
    self: *Coroutine,
    comptime routine: anytype,
    args: anytype,
    allocator: Allocator,
) !void {
    const stack = try Stack.init(allocator);
    return self.initWithStack(
        stack,
        routine,
        args,
        allocator,
    );
}

pub fn initWithStack(
    self: *Coroutine,
    stack: Stack,
    comptime routine: anytype,
    args: anytype,
    allocator: Allocator,
) !void {
    //TODO: consider allocating this closure on the coroutine stack?
    const closure = try Closure.init(
        routine,
        args,
        allocator,
    );
    self.* = .{
        .stack = stack,
        .routine = &closure.runnable,
    };
    self.execution_context.init(
        stack,
        self.trampoline(),
    );
}

fn trampoline(self: *Coroutine) Trampoline {
    return Trampoline{
        .ptr = self,
        .vtable = &.{
            .run = run,
        },
    };
}

fn run(ctx: *anyopaque) noreturn {
    var self: *Coroutine = @ptrCast(@alignCast(ctx));
    self.routine.runFn(self.routine);
    self.complete();
}

fn complete(self: *Coroutine) noreturn {
    self.is_completed = true;
    self.execution_context.exitTo(&self.previous_context);
}

pub fn deinit(self: *Coroutine) void {
    assert(self.is_completed);
    self.stack.deinit();
}

pub fn @"resume"(self: *Coroutine) void {
    self.previous_context.switchTo(&self.execution_context);
}

pub fn @"suspend"(self: *Coroutine) void {
    self.execution_context.switchTo(&self.previous_context);
}

test {
    _ = @import("./coroutine/tests.zig");
}
