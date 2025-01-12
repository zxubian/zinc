//! A thin wrapper around a raw byte buffer aligned
//! according to target architecture requirements.
const std = @import("std");
const builtin = @import("builtin");
const Stack = @This();
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const PtrType = [*]align(ALIGNMENT_BYTES) u8;

slice: []align(ALIGNMENT_BYTES) u8,

pub const ALIGNMENT_BYTES = builtin.target.stackAlignment();
pub const DEFAULT_SIZE_BYTES = 16 * 1024 * 1024;

pub fn top(self: *const Stack) PtrType {
    return @alignCast(self.slice.ptr + self.slice.len);
}

pub fn base(self: *const Stack) PtrType {
    return @alignCast(self.slice.ptr);
}

pub fn bufferAllocator(self: *const Stack) FixedBufferAllocator {
    return std.heap.FixedBufferAllocator.init(self.slice);
}

pub const Managed = struct {
    raw: Stack,
    allocator: Allocator,

    const Self = @This();
    const log = std.log.scoped(.stack);

    pub fn init(allocator: Allocator) !Self {
        return initOptions(allocator, .{});
    }

    pub const InitOptions = struct {
        size: usize = DEFAULT_SIZE_BYTES,
    };

    pub fn initOptions(
        allocator: Allocator,
        options: InitOptions,
    ) !Self {
        const size = options.size;
        const buffer = try allocator.alignedAlloc(
            u8,
            ALIGNMENT_BYTES,
            size,
        );
        return Self{
            .raw = .{
                .slice = buffer,
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.raw.slice);
    }

    pub inline fn top(self: *const Self) PtrType {
        return self.raw.top();
    }

    pub inline fn base(self: *const Self) PtrType {
        return self.raw.base();
    }

    pub inline fn bufferAllocator(
        self: *const Self,
    ) FixedBufferAllocator {
        return self.raw.bufferAllocator();
    }

    pub inline fn slice(self: *const Self) []align(ALIGNMENT_BYTES) u8 {
        return self.raw.slice;
    }
};
