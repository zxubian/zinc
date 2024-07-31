const std = @import("std");
const testing = std.testing;
const ManualExecutor = @import("../manual.zig");
const Executor = @import("../../executors.zig").Executor;
const Runnable = @import("../../executors.zig").Runnable;

const allocator = std.testing.allocator;

test "Just Works" {
    var manual = ManualExecutor.init(allocator);
    var step: usize = 0;
    try testing.expect(manual.isEmpty());
    try testing.expect(!manual.runNext());
    try testing.expectEqual(0, manual.runAtMost(99));

    const Step = struct {
        pub fn run(step_: *usize) void {
            step_.* += 1;
        }
    };
    manual.executor.submit(Step.run, .{&step}, allocator);
    try testing.expect(!manual.isEmpty());
    try testing.expectEqual(1, manual.count());
    try testing.expectEqual(0, step);
    manual.executor.submit(Step.run, .{&step}, allocator);
    try testing.expectEqual(2, manual.count());
    try testing.expectEqual(0, step);
    try testing.expect(manual.runNext());
    try testing.expectEqual(1, step);
    manual.executor.submit(Step.run, .{&step}, allocator);
    try testing.expectEqual(2, manual.count());
    try testing.expectEqual(2, manual.runAtMost(99));
    try testing.expectEqual(3, step);
    try testing.expect(manual.isEmpty());
    try testing.expect(!manual.runNext());
}

test "Run At Most" {
    var manual = ManualExecutor.init(allocator);
    try testing.expect(manual.isEmpty());
    try testing.expect(!manual.runNext());
    try testing.expectEqual(0, manual.runAtMost(99));

    const Looper = struct {
        iterations: usize,
        manual: *ManualExecutor,
        allocator: std.mem.Allocator,

        pub fn run(self: *@This()) void {
            self.iterations -= 1;
            if (self.iterations > 0) {
                self.submit();
            }
        }

        fn submit(self: *@This()) void {
            self.manual.executor.submit(@This().run, .{self}, self.allocator);
        }

        pub fn start(self: *@This()) void {
            self.submit();
        }
    };

    var looper = Looper{
        .iterations = 256,
        .manual = &manual,
        .allocator = allocator,
    };
    looper.start();

    var step: usize = 0;
    while (!manual.isEmpty()) {
        step += manual.runAtMost(7);
    }
    try testing.expectEqual(256, step);
}

test "Drain" {
    var manual = ManualExecutor.init(allocator);

    const Looper = struct {
        iterations: usize,
        manual: *ManualExecutor,
        allocator: std.mem.Allocator,

        pub fn run(self: *@This()) void {
            self.iterations -= 1;
            if (self.iterations > 0) {
                self.submit();
            }
        }

        fn submit(self: *@This()) void {
            self.manual.executor.submit(@This().run, .{self}, self.allocator);
        }

        pub fn start(self: *@This()) void {
            self.submit();
        }
    };

    var looper = Looper{
        .iterations = 117,
        .manual = &manual,
        .allocator = allocator,
    };
    looper.start();
    try testing.expectEqual(117, manual.drain());
}
