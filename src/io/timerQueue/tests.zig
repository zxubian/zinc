const std = @import("std");
const time = std.time;
const testing = std.testing;
const gpa = testing.allocator;

const ThreadPool = @import("../executors.zig").ThreadPools.Compute;
const TimerQueue = @import("../TimerQueue.zig");

test "Timer Queue" {
    var thread_pool = try ThreadPool.init(1, gpa);
    defer thread_pool.deinit();
    try thread_pool.start();
    defer thread_pool.stop();

    var timer_queue = try TimerQueue.init(
        .{ .callback_entry_allocator = gpa },
        thread_pool.executor(),
        gpa,
    );
    defer timer_queue.deinit();

    const Ctx = struct {
        step: usize = 0,
        pub fn run(self_: ?*anyopaque) void {
            var self = @as(*@This(), @alignCast(@ptrCast(self_)));
            self.step += 1;
        }
    };

    var ctx = Ctx{};

    try timer_queue.submit(
        time.ns_per_s * 3,
        Ctx.run,
        &ctx,
    );
    thread_pool.waitIdle();

    try testing.expectEqual(1, ctx.step);
}
