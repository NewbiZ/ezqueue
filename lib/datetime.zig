const std = @import("std");
const libc = @import("libc.zig");

pub fn formatTime(timestamp: u64) [19]u8 {
    const timestamp_s: i64 = @intCast(timestamp);
    var tm: libc.struct_tm = undefined;
    _ = libc.localtime_r(&timestamp_s, &tm);
    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(
        &buf,
        "{:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
        .{
            @as(u16, @intCast(tm.tm_year + 1900)),
            @as(u16, @intCast(tm.tm_mon + 1)),
            @as(u16, @intCast(tm.tm_mday)),
            @as(u16, @intCast(tm.tm_hour)),
            @as(u16, @intCast(tm.tm_min)),
            @as(u16, @intCast(tm.tm_sec)),
        },
    ) catch unreachable;
    return buf;
}

pub fn formatCurrentTime() [19]u8 {
    const now = std.time.timestamp();
    return formatTime(@intCast(now));
}
