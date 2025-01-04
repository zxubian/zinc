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

runnable: *Runnable = undefined,
stack: Stack = undefined,
previous_context: ExecutionContext = .{},
execution_context: ExecutionContext = .{},
is_completed: bool = false,

pub fn init(
    comptime routine: anytype,
    args: std.meta.ArgsTuple(@TypeOf(routine)),
    gpa: Allocator,
) !Managed {
    return try initOptions(routine, args, gpa, .{});
}

pub const Options = struct {
    stack_size: usize = Stack.DEFAULT_SIZE_BYTES,
};

pub fn initOptions(
    comptime routine: anytype,
    args: std.meta.ArgsTuple(@TypeOf(routine)),
    /// only used for allocating stack
    gpa: Allocator,
    options: Options,
) !Managed {
    const stack = try Stack.Managed.initOptions(gpa, .{ .size = options.stack_size });
    var fixed_buffer_allocator = stack.bufferAllocator();
    const stack_gpa = fixed_buffer_allocator.allocator();
    const self = try initOnStack(routine, args, stack, stack_gpa);
    return Managed{
        .coroutine = self,
        .stack = stack,
    };
}

pub fn initOnStack(
    comptime routine: anytype,
    args: std.meta.ArgsTuple(@TypeOf(routine)),
    stack: Stack,
    stack_arena: Allocator,
) !*Coroutine {
    const self = try stack_arena.create(Coroutine);
    const routine_closure = try stack_arena.create(Closure.Impl(routine, false));
    routine_closure.init(args);
    self.initNoAlloc(
        &routine_closure.*.runnable,
        stack,
    );
    return self;
}

pub fn initWithStack(
    self: *Coroutine,
    comptime routine: anytype,
    args: std.meta.ArgsTuple(@TypeOf(routine)),
    stack: Stack,
    gpa: Allocator,
) !void {
    const routine_closure = try Closure.init(
        routine,
        args,
        gpa,
    );
    self.initNoAlloc(
        &routine_closure.*.runnable,
        stack,
    );
}

pub fn initNoAlloc(
    self: *Coroutine,
    runnable: *Runnable,
    stack: Stack,
) void {
    self.* = .{
        .runnable = runnable,
        .stack = stack,
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
    self.runnable.run();
    self.complete();
}

fn complete(self: *Coroutine) noreturn {
    self.is_completed = true;
    self.execution_context.exitTo(&self.previous_context);
}

pub fn @"resume"(self: *Coroutine) void {
    self.previous_context.switchTo(&self.execution_context);
}

pub fn @"suspend"(self: *Coroutine) void {
    self.execution_context.switchTo(&self.previous_context);
}

pub const Managed = struct {
    coroutine: Coroutine,
    stack: Stack.Managed,

    pub fn initInPlace(
        self: *@This(),
        comptime routine: anytype,
        args: std.meta.ArgsTuple(@TypeOf(routine)),
        gpa: Allocator,
    ) !void {
        self.stack = try Stack.Managed.init(gpa);
        // TODO: use initOnStack here
        try self.coroutine.initWithStack(routine, args, self.stack.raw, gpa);
    }

    pub fn deinit(self: *@This()) void {
        self.stack.deinit();
    }

    pub inline fn @"resume"(self: *Managed) void {
        self.coroutine.@"resume"();
    }

    pub inline fn @"suspend"(self: *Managed) void {
        self.coroutine.@"suspend"();
    }

    pub inline fn isCompleted(self: *const Managed) bool {
        return self.coroutine.is_completed;
    }
};

test {
    _ = @import("./coroutine/tests.zig");
}
