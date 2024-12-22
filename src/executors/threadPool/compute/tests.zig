const std = @import("std");
const builtin = @import("builtin");
const ThreadPool = @import("../compute.zig");
const testing = std.testing;
const TimeLimit = @import("../../../testing/TimeLimit.zig");
const Allocator = std.mem.Allocator;
const WaitGroup = std.Thread.WaitGroup;

test "Submit Lambda" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(1, alloc);
    defer tp.deinit();

    const Context = struct {
        a: usize,
        wait_group: WaitGroup = .{},
        pub fn run(self: *@This()) void {
            self.a += 1;
            self.wait_group.finish();
        }
    };
    var ctx = Context{ .a = 0 };
    const executor = tp.executor();

    ctx.wait_group.start();
    executor.submit(Context.run, .{&ctx}, alloc);
    try testing.expectEqual(0, ctx.a);

    try tp.start();
    defer tp.stop();
    ctx.wait_group.wait();
    ctx.wait_group.reset();
    try testing.expectEqual(1, ctx.a);

    ctx.wait_group.start();
    executor.submit(Context.run, .{&ctx}, alloc);
    ctx.wait_group.wait();
    ctx.wait_group.reset();
    try testing.expectEqual(2, ctx.a);

    ctx.wait_group.startMany(2);
    executor.submit(Context.run, .{&ctx}, alloc);
    executor.submit(Context.run, .{&ctx}, alloc);
    ctx.wait_group.wait();
    ctx.wait_group.reset();
    try testing.expectEqual(4, ctx.a);
}

test "Wait" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(1, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    const Context = struct {
        done: bool,
        wait_group: WaitGroup = .{},
        pub fn run(self: *@This()) void {
            std.time.sleep(std.time.ns_per_ms);
            self.done = true;
            self.wait_group.finish();
        }
    };
    var ctx = Context{ .done = false };
    const executor = tp.executor();
    ctx.wait_group.start();
    executor.submit(Context.run, .{&ctx}, alloc);
    ctx.wait_group.wait();
    try testing.expect(ctx.done);
}

test "Multi-wait" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(1, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    var wait_group: WaitGroup = .{};
    const Context = struct {
        done: bool,
        wait_group: *WaitGroup,
        pub fn run(self: *@This()) void {
            std.time.sleep(std.time.ns_per_ms);
            self.done = true;
            self.wait_group.finish();
        }
    };
    const executor = tp.executor();
    const count = 3;
    var contexts: [count]Context = [_]Context{.{
        .done = false,
        .wait_group = &wait_group,
    }} ** count;
    wait_group.startMany(count);
    for (&contexts) |*ctx| {
        executor.submit(Context.run, .{ctx}, alloc);
    }
    wait_group.wait();
    for (contexts) |ctx| {
        try testing.expect(ctx.done);
    }
}

test "Many Tasks" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(4, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    const task_count: usize = 17;
    const Context = struct {
        tasks: std.atomic.Value(usize),
        wait_group: WaitGroup = .{},
        pub fn run(self: *@This()) void {
            _ = self.tasks.fetchAdd(1, .seq_cst);
            self.wait_group.finish();
        }
    };
    var ctx = Context{ .tasks = std.atomic.Value(usize).init(0) };
    const executor = tp.executor();
    ctx.wait_group.startMany(task_count);
    for (0..task_count) |_| {
        executor.submit(Context.run, .{&ctx}, alloc);
    }
    ctx.wait_group.wait();
    try testing.expectEqual(task_count, ctx.tasks.load(.seq_cst));
}

test "Parallel" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(4, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    const Context = struct {
        tasks: std.atomic.Value(usize) = .init(0),
        wait_group: WaitGroup = .{},
        pub fn Run(
            self: *@This(),
            sleep_nanoseconds: u64,
        ) void {
            if (sleep_nanoseconds > 0) {
                std.time.sleep(sleep_nanoseconds);
            }
            _ = self.tasks.fetchAdd(1, .seq_cst);
            self.wait_group.finish();
        }
    };
    var ctx = Context{};
    const executor = tp.executor();
    ctx.wait_group.startMany(2);
    executor.submit(Context.Run, .{ &ctx, std.time.ns_per_s }, alloc);
    executor.submit(Context.Run, .{ &ctx, 0 }, alloc);
    std.time.sleep(std.time.ns_per_ms * 500);
    try testing.expectEqual(1, ctx.tasks.load(.seq_cst));
    ctx.wait_group.wait();
    try testing.expectEqual(2, ctx.tasks.load(.seq_cst));
}

test "Two Pools" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp1 = try ThreadPool.init(1, alloc);
    var tp2 = try ThreadPool.init(1, alloc);
    defer tp1.deinit();
    defer tp2.deinit();
    try tp1.start();
    try tp2.start();
    defer tp1.stop();
    defer tp2.stop();

    const Context = struct {
        tasks: std.atomic.Value(usize) = .init(0),
        wait_group: WaitGroup = .{},

        const sleep_nanoseconds: u64 = std.time.ns_per_s;

        pub fn Run(self: *@This()) void {
            std.time.sleep(sleep_nanoseconds);
            _ = self.tasks.fetchAdd(1, .seq_cst);
            self.wait_group.finish();
        }
    };
    var ctx = Context{};

    var timer = try std.time.Timer.start();

    ctx.wait_group.startMany(2);
    tp1.executor().submit(Context.Run, .{&ctx}, alloc);
    tp2.executor().submit(Context.Run, .{&ctx}, alloc);

    ctx.wait_group.wait();

    const elapsed_ns = timer.read();
    try testing.expectEqual(2, ctx.tasks.load(.seq_cst));
    try testing.expect(elapsed_ns / std.time.ns_per_ms < 1500);
}

test "Stop" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(1, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    const Context = struct {
        wait_group: WaitGroup = .{},
        pub fn Run(self: *@This()) void {
            std.time.sleep(std.time.ns_per_ms * 128);
            self.wait_group.finish();
        }
    };
    var ctx = Context{};
    const executor = tp.executor();
    ctx.wait_group.startMany(3);
    for (0..3) |_| {
        executor.submit(Context.Run, .{&ctx}, alloc);
    }
    ctx.wait_group.wait();
    try testing.expectEqual(0, tp.tasks.backing_queue.count);
}

test "Current" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(1, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    try std.testing.expectEqual(null, ThreadPool.current());
    const Context = struct {
        tp: *ThreadPool,
        wait_group: WaitGroup = .{},
        pub fn Run(self: *@This()) void {
            const c = ThreadPool.current();
            std.testing.expectEqual(self.tp, c) catch std.debug.panic(
                "Expected: {?} Got: {?}",
                .{ self.tp, c },
            );
            self.wait_group.finish();
        }
    };
    var ctx = Context{ .tp = &tp };
    const executor = tp.executor();
    ctx.wait_group.start();
    executor.submit(Context.Run, .{&ctx}, alloc);
    ctx.wait_group.wait();
}

test "Submit after waitgroup finish" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(1, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();
    var wait_group: WaitGroup = .{};
    wait_group.startMany(2);

    const ContextB = struct {
        done: *bool,
        alloc: Allocator,
        wait_group: *WaitGroup,

        pub fn Run(self: *@This()) void {
            var wg = self.wait_group;
            std.time.sleep(std.time.ns_per_ms * 500);
            self.done.* = true;
            self.alloc.destroy(self);
            wg.finish();
        }
    };
    const ContextA = struct {
        done: *bool,
        alloc: Allocator,
        wait_group: *WaitGroup,

        pub fn Run(self: *@This()) void {
            std.time.sleep(std.time.ns_per_ms * 500);
            // must allocate on heap:
            // if we allocate on stack, then ptr to ctx will be destroyed
            // as soon as ContextA.Run exits, but before ContextB.Run accesses
            // its "self" ptr ptr, leading to segfault.
            const ctx = self.alloc.create(ContextB) catch unreachable;
            ctx.* = .{
                .done = self.done,
                .alloc = self.alloc,
                .wait_group = self.wait_group,
            };
            ThreadPool.current().?.executor().submit(ContextB.Run, .{ctx}, self.alloc);
            self.wait_group.finish();
        }
    };
    var done = false;
    var ctx = ContextA{
        .done = &done,
        .alloc = alloc,
        .wait_group = &wait_group,
    };
    const executor = tp.executor();
    executor.submit(ContextA.Run, .{&ctx}, alloc);
    wait_group.wait();
    try testing.expectEqual(true, done);
}

test "Use Threads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var limit = try TimeLimit.init(std.time.ns_per_s);
    {
        var thread_safe_alloc = std.heap.ThreadSafeAllocator{
            .child_allocator = std.testing.allocator,
            .mutex = .{},
        };
        const alloc = thread_safe_alloc.allocator();

        var tp = try ThreadPool.init(4, alloc);
        defer tp.deinit();
        try tp.start();
        defer tp.stop();

        const task_count: usize = 4;

        const Context = struct {
            tasks: std.atomic.Value(usize),
            wait_group: WaitGroup = .{},

            pub fn run(self: *@This()) void {
                std.time.sleep(std.time.ns_per_ms * 750);
                _ = self.tasks.fetchAdd(1, .seq_cst);
                self.wait_group.finish();
            }
        };

        var ctx = Context{ .tasks = std.atomic.Value(usize).init(0) };
        const executor = tp.executor();
        for (0..task_count) |_| {
            ctx.wait_group.start();
            executor.submit(Context.run, .{&ctx}, alloc);
        }
        ctx.wait_group.wait();
        try testing.expectEqual(task_count, ctx.tasks.load(.seq_cst));
    }
    try limit.check();
}

test "Too Many Threads" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var limit = try TimeLimit.init(std.time.ns_per_s * 2);
    {
        var thread_safe_alloc = std.heap.ThreadSafeAllocator{
            .child_allocator = std.testing.allocator,
            .mutex = .{},
        };
        const alloc = thread_safe_alloc.allocator();

        var tp = try ThreadPool.init(3, alloc);
        defer tp.deinit();
        try tp.start();
        defer tp.stop();

        const task_count: usize = 4;

        const Context = struct {
            tasks: std.atomic.Value(usize),
            wait_group: WaitGroup = .{},

            pub fn run(self: *@This()) void {
                std.time.sleep(std.time.ns_per_ms * 750);
                _ = self.tasks.fetchAdd(1, .seq_cst);
                self.wait_group.finish();
            }
        };

        var ctx = Context{ .tasks = std.atomic.Value(usize).init(0) };
        const executor = tp.executor();
        for (0..task_count) |_| {
            ctx.wait_group.start();
            executor.submit(Context.run, .{&ctx}, alloc);
        }
        ctx.wait_group.wait();
        try testing.expectEqual(task_count, ctx.tasks.load(.seq_cst));
    }
    try limit.check();
}

test "Keep Alive" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var limit = try TimeLimit.init(std.time.ns_per_s * 4);
    {
        var thread_safe_alloc = std.heap.ThreadSafeAllocator{
            .child_allocator = std.testing.allocator,
            .mutex = .{},
        };
        const alloc = thread_safe_alloc.allocator();

        var tp = try ThreadPool.init(3, alloc);
        defer tp.deinit();
        var wait_group: WaitGroup = .{};
        try tp.start();
        defer tp.stop();

        const Context = struct {
            pub fn run(
                limit_: *TimeLimit,
                alloc_: Allocator,
                wait_group_: *WaitGroup,
            ) void {
                if (limit_.remaining() > std.time.ns_per_ms * 300) {
                    wait_group_.start();
                    ThreadPool.current().?.executor().submit(
                        @This().run,
                        .{
                            limit_,
                            alloc_,
                            wait_group_,
                        },
                        alloc_,
                    );
                }
                wait_group_.finish();
            }
        };
        const executor = tp.executor();
        for (0..5) |_| {
            wait_group.start();
            executor.submit(Context.run, .{ &limit, alloc, &wait_group }, alloc);
        }
        var timer = try std.time.Timer.start();
        wait_group.wait();
        try testing.expect(timer.read() > std.time.ns_per_s * 3);
    }
    try limit.check();
}

test "Racy" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    var thread_safe_alloc = std.heap.ThreadSafeAllocator{
        .child_allocator = std.testing.allocator,
        .mutex = .{},
    };
    const alloc = thread_safe_alloc.allocator();

    var tp = try ThreadPool.init(4, alloc);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    const task_count: usize = 100500;
    var sharead_counter = std.atomic.Value(usize).init(0);

    const Context = struct {
        shared_counter: *std.atomic.Value(usize),
        wait_group: WaitGroup = .{},
        pub fn run(self: *@This()) void {
            const old = self.shared_counter.load(.seq_cst);
            self.shared_counter.store(old + 1, .seq_cst);
            self.wait_group.finish();
        }
    };

    var ctx = Context{
        .shared_counter = &sharead_counter,
    };
    const executor = tp.executor();
    for (0..task_count) |_| {
        ctx.wait_group.start();
        executor.submit(Context.run, .{&ctx}, alloc);
    }
    ctx.wait_group.wait();
    try testing.expect(sharead_counter.load(.seq_cst) <= task_count);
}
