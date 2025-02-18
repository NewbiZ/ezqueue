const std = @import("std");

const libezqueue = @import("libezqueue");
const libc = libezqueue.libc;
const z = libc.z;
const log = std.log;
const errnocall = libc.errnocall;
const errnocall_nr = libc.errnocall_nr;
const Consumer = libezqueue.spsc.Consumer;
const Producer = libezqueue.spsc.Producer;

const QUEUE_SIZE = 1 * 1024 * 1024 * 1024;

pub const std_options = std.Options{
    .logFn = libezqueue.logging.log,
};

pub fn producer(dir: []const u8) !void {
    try libezqueue.process.pin_to_core(0);

    var p = Producer.init(.{
        .name = "ezqueue",
        .capacity = QUEUE_SIZE,
        .dir = dir,
    }) catch |err| {
        log.err("Failed to init producer: {any}", .{err});
        std.process.exit(1);
    };
    defer p.deinit() catch unreachable;

    var count: u64 = 0;
    const t1 = std.time.milliTimestamp();
    while (count < 10000000) {
        const bytes = p.push(8) catch continue;
        const num: *align(1) u64 = @ptrCast(bytes.ptr);
        num.* = count;
        p.commit(8);
        count += 1;
    }
    const t2 = std.time.milliTimestamp();

    //std.debug.print("p:elapsed time    = {d} ms\n", .{t2 -% t1});
    std.debug.print("p:throughput      = {d:>.3} Mm/s\n", .{@as(f64, @floatFromInt(10000000)) / @as(f64, @floatFromInt(t2 - t1)) * 1000.0 / 1000000});
}

pub fn consumer(dir: []const u8) !void {
    try libezqueue.process.pin_to_core(1);

    var c = Consumer.initBlock(1000, .{
        .name = "ezqueue",
        .dir = dir,
    }) catch |err| {
        log.err("Failed to init consumer: {any}", .{err});
        std.process.exit(1);
    };
    defer c.deinit() catch unreachable;

    var count: u64 = 0;
    const t1 = std.time.milliTimestamp();
    var res: u64 = 0;
    while (count < 10000000) {
        const bytes = c.pop() catch |err| switch (err) {
            error.Empty => continue,
            error.Eof => break,
        };
        const num_ptr: *align(1) const u64 = @ptrCast(bytes.ptr);
        res = num_ptr.*;
        c.commit(8);
        count += 1;
    }
    const t2 = std.time.milliTimestamp();

    //std.debug.print("c:res             = 0x{d}\n", .{res});
    //std.debug.print("c:elapsed time    = {d} ms\n", .{t2 -% t1});
    std.debug.print("c:throughput      = {d:>.3} Mm/s\n", .{@as(f64, @floatFromInt(10000000)) / @as(f64, @floatFromInt(t2 - t1)) * 1000.0 / 1000000});
}

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch |err| {
        log.err("Failed to allocate args: {any}", .{err});
        std.process.exit(1);
    };
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <shm dir>\n", .{args[0]});
        return;
    }

    const dir = args[1];

    const p = std.Thread.spawn(.{}, producer, .{dir}) catch |err| {
        log.err("Failed to spawn producer: {any}", .{err});
        std.process.exit(1);
    };
    const c = std.Thread.spawn(.{}, consumer, .{dir}) catch |err| {
        log.err("Failed to spawn consumer: {any}", .{err});
        std.process.exit(1);
    };

    p.setName("producer") catch |err| {
        log.err("Failed to set producer name: {any}", .{err});
        std.process.exit(1);
    };
    c.setName("consumer") catch |err| {
        log.err("Failed to set consumer name: {any}", .{err});
        std.process.exit(1);
    };

    p.join();
    c.join();
}
