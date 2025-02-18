const std = @import("std");

const libezqueue = @import("libezqueue");
const libc = libezqueue.libc;
const z = libc.z;
const log = std.log;
const errnocall = libc.errnocall;
const errnocall_nr = libc.errnocall_nr;
const Consumer = libezqueue.spsc.Consumer;
const Producer = libezqueue.spsc.Producer;

const QUEUE_SIZE = 64 * 1024 * 1024;

pub const std_options = std.Options{
    .logFn = libezqueue.logging.log,
};

pub fn producer(input: []const u8, dir: []const u8) !void {
    try libezqueue.process.pin_to_core(0);

    var p = Producer.init(.{
        .name = "ezqueue",
        .capacity = QUEUE_SIZE,
        .dir = dir,
    }) catch |err| {
        log.err("Failed to init producer: {any}", .{err});
        std.process.exit(1);
    };
    defer p.deinit() catch |err| {
        log.err("Failed to deinit producer: {any}", .{err});
        std.process.exit(1);
    };

    const fd = errnocall(libc.open, .{
        &(z(input) catch |err| {
            log.err("Failed to convert input file path: {any}", .{err});
            std.process.exit(1);
        }),
        libc.O_CLOEXEC | libc.O_RDONLY | libc.O_DIRECT,
    }) catch |err| {
        log.err("Failed to open input file: {any}", .{err});
        std.process.exit(1);
    };
    defer errnocall_nr(libc.close, .{fd}) catch |err| {
        log.err("Failed to close input file: {any}", .{err});
        std.process.exit(1);
    };

    const page_size = p.page_size();
    var read_count: u64 = 0;
    var read_sz: u64 = 0;
    const t1 = std.time.milliTimestamp();
    while (true) {
        const free_pages = p.free() / page_size;
        if (free_pages == 0)
            continue;
        const free_size = @min(free_pages * page_size, libc.SSIZE_MAX);
        const buffer = p.push(free_size) catch unreachable;
        const rc = errnocall(libc.read, .{ fd, buffer.ptr, free_size }) catch |err| {
            log.err("Failed to read input file: {any}", .{err});
            std.process.exit(1);
        };
        read_count += 1;
        read_sz += @intCast(rc);
        if (rc == 0) {
            break;
        }
        p.commit(@bitCast(rc));
    }
    const t2 = std.time.milliTimestamp();

    std.debug.print("p:read count      = x{d} \n", .{read_count});
    std.debug.print("p:read size       = {d} MB\n", .{read_sz / 1024 / 1024});
    std.debug.print("p:read throughput = {d:>.3} GB/s\n", .{
        @as(f64, @floatFromInt(read_sz / 1024 / 1024 / 1024)) / @as(f64, @floatFromInt(t2 - t1)) * 1000.0,
    });
    std.debug.print("p:elapsed time    = {d} ms\n", .{t2 -% t1});
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
    defer c.deinit() catch |err| {
        log.err("Failed to deinit consumer: {any}", .{err});
        std.process.exit(1);
    };

    var read_count: u64 = 0;
    var read_sz: u64 = 0;
    var spins: u64 = 0;
    while (true) {
        const bytes = c.pop() catch |err| switch (err) {
            error.Empty => {
                spins += 1;
                continue;
            },
            error.Eof => break,
        };
        c.commit(bytes.len);

        read_count += 1;
        read_sz += bytes.len;
    }
    std.debug.print("c:read count      = {d}\n", .{read_count});
    std.debug.print("c:read size       = {d} MB\n", .{read_sz / 1024 / 1024});
    std.debug.print("c:spins           = {d}\n", .{spins});
}

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch |err| {
        log.err("Failed to allocate args: {any}", .{err});
        std.process.exit(1);
    };
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} <input file> <shm dir>\n", .{args[0]});
        return;
    }

    const input = args[1];
    const dir = args[2];

    const p = std.Thread.spawn(.{}, producer, .{ input, dir }) catch |err| {
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
