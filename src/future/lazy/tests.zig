const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const assert = std.debug.assert;
const executors = @import("../../main.zig").executors;
const future = @import("../main.zig").lazy;

test "lazy future - just - basic" {
    const just = future.just();
    try future.get(just);
}

test "lazy future - value - basic" {
    const value = future.value(@as(usize, 44));
    const result = try future.get(value);
    try testing.expectEqual(44, result);
}

test "lazy future - pipeline - basic" {
    const value = future.value(@as(usize, 44));
    const via = future.via(executors.@"inline").pipe(value);
    const map = future.map(struct {
        pub fn run(
            _: ?*anyopaque,
            in: usize,
        ) usize {
            return in + 1;
        }
    }.run, null).pipe(via);
    const result = try future.get(map);
    try testing.expectEqual(45, result);
}

test "lazy future - pipeline - multiple" {
    const value = future.value(@as(usize, 0));
    const via = future.via(executors.@"inline").pipe(value);
    const map = future.map(struct {
        pub fn run(
            _: ?*anyopaque,
            in: usize,
        ) usize {
            return in + 1;
        }
    }.run, null).pipe(via);
    const map_2 = future.map(struct {
        pub fn run(
            _: ?*anyopaque,
            in: usize,
        ) usize {
            return in + 2;
        }
    }.run, null).pipe(map);
    const result = try future.get(map_2);
    try testing.expectEqual(3, result);
}

test "lazy future map - with side effects" {
    const just = future.just();
    const via = future.via(executors.@"inline").pipe(just);
    var done: bool = false;
    const map = future.map(struct {
        pub fn run(
            ctx: ?*anyopaque,
        ) void {
            const done_: *bool = @alignCast(@ptrCast(ctx));
            done_.* = true;
        }
    }.run, @alignCast(@ptrCast(&done))).pipe(via);
    try future.get(map);
    try testing.expect(done);
}

test "lazy future - pipeline - syntax" {
    const pipeline = future.pipeline(
        .{
            future.value(@as(u32, 123)),
            future.via(executors.@"inline"),
            future.map(struct {
                pub fn run(
                    _: ?*anyopaque,
                    in: u32,
                ) u32 {
                    return in + 1;
                }
            }.run, null),
        },
    );
    const result = try future.get(pipeline);
    try testing.expectEqual(124, result);
}

test "lazy future - submit - basic" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }
    const allocator = testing.allocator;
    var pool: executors.ThreadPools.Compute = try .init(1, allocator);
    defer pool.deinit();
    try pool.start();
    defer pool.stop();
    const compute = future.submit(
        pool.executor(),
        struct {
            pub fn run(_: ?*anyopaque) usize {
                return 11;
            }
        }.run,
        null,
    );
    const result: usize = try future.get(compute);
    try testing.expectEqual(11, result);
}
