const Runnable = @This();
pub const RunProto = *const fn (runnable: *Runnable) void;

run: RunProto,
