const std = @import("std");

pub const Producer = @import("spsc/Producer.zig");
pub const Consumer = @import("spsc/Consumer.zig");

/// Size of a L1 cache line, to avoid false sharing between producer and consumer
pub const CACHE_LINE_SIZE = 64;
/// Version of the ringbuffer ABI supported by this code
pub const QUEUE_VERSION = 1;
/// Maximum size of a ringbuffer name
pub const NAME_MAX = 128;

pub const Header = extern struct {
    version: u64,
    capacity: u64,
    page_size: u64,
    head: u64 align(CACHE_LINE_SIZE),
    eof: u64 align(CACHE_LINE_SIZE),
    tail: u64 align(CACHE_LINE_SIZE),
};

test "wrap-around" {
    var p = try Producer.init(.{
        .name = "test",
        .capacity = 4096,
        .dir = "/dev/shm",
    });
    defer p.deinit() catch unreachable;

    var c = try Consumer.init(.{
        .name = "test",
        .dir = "/dev/shm",
    });
    defer c.deinit() catch unreachable;

    // Fill the ringbuffer except the last 4 bytes
    _ = try p.push(4092);
    p.commit(4092);
    _ = try c.pop();
    c.commit(4092);

    // Now push 8 bytes (as u64) and read them as a contiguous buffer
    {
        const bytes = try p.push(8);
        const num: *align(1) u64 = @ptrCast(bytes.ptr);
        num.* = 0x0102030405060708;
        p.commit(8);
    }
    {
        const bytes = try c.pop();
        try std.testing.expectEqual(8, bytes.len);
        const num: *align(1) const u64 = @ptrCast(bytes.ptr);
        try std.testing.expectEqual(0x0102030405060708, num.*);
        c.commit(8);
    }
}
