const Producer = @This();

const std = @import("std");
const log = std.log;
const fmt = std.fmt;

const libc = @import("../libc.zig");
const errnocall = libc.errnocall;
const errnocall_nr = libc.errnocall_nr;
const z = libc.z;

const spsc = @import("../spsc.zig");
const Header = spsc.Header;

const QUEUE_VERSION = spsc.QUEUE_VERSION;
const NAME_MAX = spsc.NAME_MAX;

/// File descriptor of the directory where the shared memory is located, the name of the ringbuffer
/// references a file in this directory, thus this fd is kept open for the duration of the producer
/// lifetime
dirfd: libc.fd_t,
/// Zero terminated string name of the ringbuffer. This is kept for the duration of the producer
/// lifetime, at which point the ringbuffer is unlinked from the filesystem
namez: [NAME_MAX:0]u8,
/// Pointer to the ringbuffer header in shared memory
header: *align(64) Header,
/// Pointer to the ringbuffer data in shared memory, this is twice the actual capacity of the ringbuffer
/// so that contiguous access to wrapped-around buffers is possible
data: []align(std.mem.page_size) u8,
/// This is a boolean keeping track of the amount of data reserved during 2-staged push
reserved: u64,
/// Thread-local cache of the ringbuffer's tail
local_tail: u64,
/// Pre-computed cache of the index mask
local_mask: u64,
/// Pre-computed cache of the ringbuffer capacity
local_capacity: u64,

const InitArgs = struct {
    /// Name of the ringbuffer
    name: []const u8,
    /// Capacity of the ringbuffer, this should be a power of 2 and a multiple of the page size
    capacity: u64,
    /// Directory in which the ringbuffer will be created. This should be a ramfs (either tmpfs or hugetlbfs)
    dir: []const u8 = "/dev/shm",
    /// Creation mode of the ringbuffer
    mode: libc.mode_t = 0o660,
};

const IOError = error{
    /// Not enough space in the ringbuffer to reserve that amount of memory
    Full,
};

const InitError = error{
    /// The ringbuffer should only be created in a ramfs: either tmpfs or hugetlbfs
    NotARamFs,
    /// Ringbuffer capacity should be a power of 2 and a multiple of the page size
    InvalidCapacity,
    /// The ringbuffer name is too long
    NameTooLong,
};

pub fn init(args: InitArgs) !Producer {
    // Sanity checks
    if (args.name.len >= NAME_MAX) {
        log.err(
            "Queue name \"{s}\" ({d} characters) is too long (max: {d})",
            .{ args.name, args.name.len, NAME_MAX - 1 },
        );
        return error.NameTooLong;
    }

    // Open the directory in which the shared memory will be located
    const dirfd = try errnocall(libc.open, .{
        &try z(args.dir),
        libc.O_CLOEXEC | libc.O_RDONLY | libc.O_DIRECTORY | libc.O_PATH,
        @as(libc.mode_t, 0o600),
    });
    errdefer errnocall_nr(libc.close, .{dirfd}) catch unreachable;

    // Since we are using file-backed shared memory, make sure it resides in a
    // ramfs: either a tmpfs or hugetlbfs filesystem
    var statfsbuf: libc.struct_statfs = undefined;
    try errnocall_nr(libc.fstatfs, .{ dirfd, &statfsbuf });
    switch (statfsbuf.f_type) {
        libc.MAGIC.TMPFS, libc.MAGIC.HUGETLBFS => {},
        else => return InitError.NotARamFs,
    }
    const page_sz = statfsbuf.f_bsize;

    // Capacity should be a multiple of the page size, since we are going to map the
    // ringbuffer two times contiguously
    if (args.capacity % page_sz != 0) {
        log.err(
            "Requested capacity ({d}) is not a multiple of the page size ({d})",
            .{ fmt.fmtIntSizeBin(args.capacity), fmt.fmtIntSizeBin(page_sz) },
        );
        return error.InvalidCapacity;
    }
    // Capacity should also be a power of 2 since we will allow read and write pointers
    // to free roll
    if (args.capacity <= 4 or args.capacity & (args.capacity - 1) != 0) {
        log.err(
            "Requested capacity ({d}) is not a power of 2 >= 4 bytes",
            .{fmt.fmtIntSizeBin(args.capacity)},
        );
        return error.InvalidCapacity;
    }

    // Open a file for the shared memory, but do not expose it on the filesystem yet
    const fd = try errnocall(libc.open, .{
        &try z(args.dir),
        libc.O_CLOEXEC | libc.O_TMPFILE | libc.O_RDWR,
        args.mode,
    });
    defer errnocall_nr(libc.close, .{fd}) catch unreachable;

    try errnocall_nr(libc.ftruncate, .{
        fd,
        @as(libc.off_t, @intCast(page_sz + args.capacity)),
    });

    const hugetlb_flags: c_int = switch (page_sz) {
        4 * 1024 => 0,
        2 * 1024 * 1024 => libc.MAP_HUGE_2MB,
        1 * 1024 * 1024 * 1024 => libc.MAP_HUGETLB | libc.MAP_HUGE_1GB,
        else => unreachable,
    };

    // Reserve a block of contiguous virtual memory for:
    // - 1 whole page for the header
    // - N pages for the actual ringbuffer
    // - N pages for a identical mapping of the ringbuffer
    const mem = (try errnocall(libc.mmap, .{
        null,
        args.capacity * 2 + page_sz,
        libc.PROT_NONE,
        libc.MAP_ANONYMOUS | libc.MAP_PRIVATE | hugetlb_flags,
        -1,
        0,
    })).?;

    // Map the first page for the header
    try errnocall_nr(libc.mmap, .{
        mem,
        page_sz,
        libc.PROT_READ | libc.PROT_WRITE,
        libc.MAP_FIXED | libc.MAP_SHARED | hugetlb_flags,
        fd,
        0,
    });

    // Map the N consecutive pages for the actual ringbuffer
    try errnocall_nr(libc.mmap, .{
        @as(*anyopaque, @ptrFromInt(@intFromPtr(mem) + page_sz)),
        args.capacity,
        libc.PROT_READ | libc.PROT_WRITE,
        libc.MAP_FIXED | libc.MAP_SHARED | hugetlb_flags,
        fd,
        @as(c_long, @intCast(page_sz)),
    });

    // Map the N consecutive pages for an identical mapping of the previous region
    try errnocall_nr(libc.mmap, .{
        @as(*anyopaque, @ptrFromInt(@intFromPtr(mem) + page_sz + args.capacity)),
        args.capacity,
        libc.PROT_READ | libc.PROT_WRITE,
        libc.MAP_FIXED | libc.MAP_SHARED | hugetlb_flags,
        fd,
        @as(c_long, @intCast(page_sz)),
    });
    const header: *Header = @as(*Header, @ptrCast(@alignCast(mem)));
    const data: []align(std.mem.page_size) u8 = @as([*]align(std.mem.page_size) u8, @ptrFromInt(@intFromPtr(mem) + page_sz))[0 .. args.capacity * 2];

    // Prefault the entire ringbuffer to ensure physical pages are allocated
    try errnocall_nr(libc.madvise, .{ mem, page_sz + 2 * args.capacity, libc.MADV_WILLNEED });
    @memset(data, 0);

    // Fill in the shared memory with the structure of an empty ringbuffer
    header.version = QUEUE_VERSION;
    header.capacity = args.capacity;
    header.page_size = page_sz;
    @atomicStore(u64, &header.head, 0, .release);
    @atomicStore(u64, &header.tail, 0, .release);

    // Expose the shared memory on the filesystem for consumers
    try errnocall_nr(libc.linkat, .{
        fd,
        &try z(""),
        dirfd,
        &try z(args.name),
        libc.AT_EMPTY_PATH,
    });

    var producer = Producer{
        .dirfd = dirfd,
        .namez = undefined,
        .header = header,
        .data = data,
        .reserved = 0,
        .local_tail = 0,
        .local_mask = header.capacity - 1,
        .local_capacity = header.capacity,
    };

    @memset(&producer.namez, 0);
    @memcpy(producer.namez[0..args.name.len], args.name);

    return producer;
}

pub fn deinit(self: *Producer) !void {
    self.set_eof();
    try errnocall_nr(libc.unlinkat, .{ self.dirfd, &self.namez, 0 });
    try errnocall_nr(libc.close, .{self.dirfd});
    try errnocall_nr(libc.munmap, .{ self.header, self.header.page_size + self.header.capacity * 2 });
    self.dirfd = 0;
    self.reserved = 0;
    self.local_tail = 0;
    @memset(&self.namez, 0);
}

pub fn page_size(self: Producer) u64 {
    return self.header.page_size;
}

fn mask(self: Producer, index: u64) u64 {
    return index & self.local_mask;
}

/// Ringbuffer actual capacity
pub fn capacity(self: Producer) u64 {
    return self.local_capacity;
}

/// Is there any free space left in the ringbuffer
pub fn full(self: Producer) bool {
    const head = @atomicLoad(u64, &self.header.head, .monotonic);
    const tail = @atomicLoad(u64, &self.header.tail, .acquire);

    return self.local_capacity == head -% tail;
}

/// Is there any unread data in the ringbuffer
pub fn empty(self: Producer) bool {
    const head = @atomicLoad(u64, &self.header.head, .monotonic);
    const tail = @atomicLoad(u64, &self.header.tail, .acquire);

    return head == tail;
}

/// How much space is used in the ringbuffer
pub fn used(self: Producer) u64 {
    const head = @atomicLoad(u64, &self.header.head, .monotonic);
    const tail = @atomicLoad(u64, &self.header.tail, .acquire);

    return head -% tail;
}

/// How much space is free in the ringbuffer
pub fn free(self: Producer) u64 {
    const head = @atomicLoad(u64, &self.header.head, .monotonic);
    const tail = @atomicLoad(u64, &self.header.tail, .acquire);

    return self.local_capacity -% (head -% tail);
}

/// Retrieve a buffer in which to push new data
pub fn push(self: *Producer, size: u64) ![]u8 {
    std.debug.assert(self.reserved == 0);
    const head = @atomicLoad(u64, &self.header.head, .monotonic);
    if (size > self.local_capacity -% (head -% self.local_tail)) {
        self.local_tail = @atomicLoad(u64, &self.header.tail, .acquire);
        if (size > self.local_capacity -% (head -% self.local_tail))
            return error.Full;
    }
    self.reserved = size;
    return self.data[self.mask(head) .. self.mask(head) +% size];
}

/// Commit the buffer retrieved from push() in the ringbuffer
pub fn commit(self: *Producer, size: u64) void {
    std.debug.assert(self.reserved > 0);
    const head = @atomicLoad(u64, &self.header.head, .monotonic);
    @atomicStore(u64, &self.header.head, head +% size, .release);
    self.reserved = 0;
}

/// Mark the ringbuffer as closed from the producer side
pub fn set_eof(self: *Producer) void {
    @atomicStore(u64, &self.header.eof, 1, .release);
}

test "name" {
    try std.testing.expectError(
        error.NameTooLong,
        Producer.init(.{
            .name = "test" ** 32,
            .capacity = 4096,
            .dir = "/dev/shm",
        }),
    );
}

test "capacity" {
    try std.testing.expectError(
        error.InvalidCapacity,
        Producer.init(.{
            .name = "test",
            .capacity = 1024,
            .dir = "/dev/shm",
        }),
    );

    try std.testing.expectError(
        error.InvalidCapacity,
        Producer.init(.{
            .name = "test",
            .capacity = 0,
            .dir = "/dev/shm",
        }),
    );
}

test "init" {
    try std.testing.expectError(
        error.FileNotFound,
        std.fs.cwd().access("/dev/shm/test", .{}),
    );
    {
        var p = try Producer.init(.{
            .name = "test",
            .capacity = 4096,
            .dir = "/dev/shm",
        });
        defer p.deinit() catch unreachable;

        try std.fs.cwd().access("/dev/shm/test", .{});

        try std.testing.expectEqual(4096, p.capacity());
        try std.testing.expectEqual(false, p.full());
        try std.testing.expectEqual(true, p.empty());
        try std.testing.expectEqual(0, p.used());
        try std.testing.expectEqual(4096, p.free());
    }
    try std.testing.expectError(
        error.FileNotFound,
        std.fs.cwd().access("/dev/shm/test", .{}),
    );
}

test "push" {
    var p = try Producer.init(.{
        .name = "test",
        .capacity = 4096,
        .dir = "/dev/shm",
    });
    defer p.deinit() catch unreachable;

    try std.testing.expectEqual(4096, p.capacity());
    try std.testing.expectEqual(false, p.full());
    try std.testing.expectEqual(true, p.empty());
    try std.testing.expectEqual(0, p.used());
    try std.testing.expectEqual(4096, p.free());

    var data: []u8 = undefined;

    data = try p.push(4090);

    try std.testing.expectEqual(4096, p.capacity());
    try std.testing.expectEqual(false, p.full());
    try std.testing.expectEqual(true, p.empty());
    try std.testing.expectEqual(0, p.used());
    try std.testing.expectEqual(4096, p.free());

    @memset(data, 0x00);
    p.commit(4090);
    p.header.tail += 4090;

    data = try p.push(10);
    @memset(data, 0xFF);
    p.commit(10);
    p.header.tail += 10;

    data = try p.push(4090);
    @memset(data, 0x11);
    p.commit(4090);
    p.header.tail += 4090;

    data = try p.push(10);
    @memset(data, 0x22);
    p.commit(10);
    p.header.tail += 10;

    try std.testing.expectEqual(4096, p.capacity());
    try std.testing.expectEqual(false, p.full());
    try std.testing.expectEqual(true, p.empty());
    try std.testing.expectEqual(0, p.used());
    try std.testing.expectEqual(4096, p.free());
}
