const Fiber = @import("../../fiber.zig");
const Mutex = Fiber.Mutex;
const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

const Executors = @import("../../executors.zig");
const ManualExecutor = Executors.Manual;
const ThreadPool = Executors.ThreadPools.Compute;
const TimeLimit = @import("../../testing/TimeLimit.zig");

test "counter" {
    var mutex: Mutex = .{};
    var manual_executor = ManualExecutor{};
    const count: usize = 100;
    const Ctx = struct {
        mutex: *Mutex,
        counter: usize,

        pub fn run(self: *@This()) void {
            for (0..count) |_| {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.counter += 1;
            }
        }
    };
    var ctx: Ctx = .{
        .mutex = &mutex,
        .counter = 0,
    };
    try Fiber.go(
        Ctx.run,
        .{&ctx},
        testing.allocator,
        manual_executor.executor(),
    );
    _ = manual_executor.drain();
    try testing.expectEqual(count, ctx.counter);
}

test "TryLock" {
    var mutex: Mutex = .{};
    var manual_executor = ManualExecutor{};
    const Ctx = struct {
        mutex: *Mutex,
        counter: usize,

        pub fn run(self: *@This()) !void {
            {
                try testing.expect(self.mutex.tryLock());
                defer self.mutex.unlock();
            }
            {
                self.mutex.lock();
                self.mutex.unlock();
            }
            try testing.expect(self.mutex.tryLock());

            var join: bool = false;
            const Outer = @This();
            const Inner = struct {
                pub fn run(join_: *bool, outer: *Outer) !void {
                    try testing.expect(!outer.mutex.tryLock());
                    join_.* = true;
                }
            };

            try Fiber.go(
                Inner.run,
                .{ &join, self },
                testing.allocator,
                Fiber.current().?.executor,
            );

            while (!join) {
                Fiber.yield();
            }
            self.mutex.unlock();
        }
    };
    var ctx: Ctx = .{
        .mutex = &mutex,
        .counter = 0,
    };
    try Fiber.go(
        Ctx.run,
        .{&ctx},
        testing.allocator,
        manual_executor.executor(),
    );
    _ = manual_executor.drain();
}

test "inner counter" {
    var mutex: Mutex = .{};
    var manual_executor = ManualExecutor{};
    const iterations_per_fiber = 5;
    const fiber_count = 5;
    var counter: usize = 0;
    const Ctx = struct {
        mutex: *Mutex,
        counter: *usize,

        pub fn run(self: *@This()) void {
            for (0..iterations_per_fiber) |_| {
                {
                    self.mutex.lock();
                    defer self.mutex.unlock();
                    self.counter.* += 1;
                }
                Fiber.yield();
            }
        }
    };
    var ctx: Ctx = .{
        .mutex = &mutex,
        .counter = &counter,
    };
    for (0..fiber_count) |_| {
        try Fiber.go(
            Ctx.run,
            .{&ctx},
            testing.allocator,
            manual_executor.executor(),
        );
    }
    _ = manual_executor.drain();
    try testing.expectEqual(
        fiber_count * iterations_per_fiber,
        counter,
    );
}

test "threadpool" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }
    var tp = try ThreadPool.init(4, testing.allocator);
    defer tp.deinit();
    try tp.start();
    defer tp.stop();

    const Ctx = struct {
        mutex: Mutex = .{},
        counter: usize = 0,
        pub fn run(ctx: *@This()) void {
            ctx.mutex.lock();
            ctx.counter += 1;
            ctx.mutex.unlock();
        }
    };

    var ctx = Ctx{};

    for (0..3) |_| {
        try Fiber.go(
            Ctx.run,
            .{&ctx},
            testing.allocator,
            tp.executor(),
        );
    }

    tp.waitIdle();
}

test "threadpool - parallel" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }
    var limit = try TimeLimit.init(std.time.ns_per_s * 5);
    {
        var tp = try ThreadPool.init(4, testing.allocator);
        defer tp.deinit();
        try tp.start();
        defer tp.stop();

        var mutex: Mutex = .{};

        const Ctx = struct {
            pub fn run(mutex_: *Mutex) void {
                mutex_.lock();
                std.Thread.sleep(std.time.ns_per_s);
                mutex_.unlock();
            }
        };

        try Fiber.go(
            Ctx.run,
            .{&mutex},
            testing.allocator,
            tp.executor(),
        );

        const Ctx2 = struct {
            pub fn run(mutex_: *Mutex) void {
                mutex_.lock();
                mutex_.unlock();
                std.Thread.sleep(std.time.ns_per_s);
            }
        };

        for (0..3) |_| {
            try Fiber.go(
                Ctx2.run,
                .{&mutex},
                testing.allocator,
                tp.executor(),
            );
        }

        tp.waitIdle();
    }
    try limit.check();
}
