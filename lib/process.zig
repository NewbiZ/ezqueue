const std = @import("std");
const libc = @import("libc.zig");

const errnocall_nr = libc.errnocall_nr;

pub fn pin_to_core(cpu: u32) !void {
    var cpu_set = std.mem.zeroes(libc.cpu_set_t);

    const set_ptr = @as([*]u8, @ptrCast(&cpu_set));
    const byte = cpu / 8;
    const bit: u3 = @intCast(cpu % 8);
    set_ptr[byte] |= @as(u8, 1) << bit;

    try errnocall_nr(libc.sched_setaffinity, .{
        0,
        @sizeOf(libc.cpu_set_t),
        &cpu_set,
    });
}
