const std = @import("std");

const datetime = @import("datetime.zig");

pub const options = std.Options{
    .logFn = log,
};

pub fn log(comptime level: std.log.Level, comptime scope: @TypeOf(.@"enum literal"), comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    const config = std.io.tty.detectConfig(std.io.getStdErr());

    const level_str = switch (level) {
        .debug => "DEBUG",
        .info => "INFO",
        .warn => "WARNING",
        .err => "ERROR",
    };

    const time_str = datetime.formatCurrentTime();

    _ = scope;

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print("{s} ", .{time_str}) catch unreachable;
        config.setColor(writer, switch (level) {
            .err => .red,
            .warn => .yellow,
            .info => .blue,
            else => .reset,
        }) catch unreachable;
        writer.print("{s} ", .{level_str}) catch unreachable;
        config.setColor(writer, .reset) catch unreachable;
        writer.print(fmt ++ "\n", args) catch unreachable;
        bw.flush() catch return;
    }
}
