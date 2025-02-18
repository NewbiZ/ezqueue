const Consumer = @This();

const std = @import("std");
const log = std.log;

const libc = @import("../libc.zig");
const errnocall = libc.errnocall;
const errnocall_nr = libc.errnocall_nr;
const z = libc.z;

const spsc = @import("../spsc.zig");
const Producer = spsc.Producer;
const Header = spsc.Header;

const QUEUE_VERSION = spsc.QUEUE_VERSION;
const NAME_MAX = spsc.NAME_MAX;

/// Pointer to the ringbuffer header in shared memory
header: *Header,
/// Pointer to the ringbuffer data in shared memory, this is twice the actual capacity of the ringbuffer
/// so that contiguous access to wrapped-around buffers is possible
data: []const u8,
/// Thread-local cache of the ringbuffer's head
local_head: u64,
/// Pre-computed cache of the index mask
local_mask: u64,
/// Pre-computed cache of the ringbuffer capacity
local_capacity: u64,

const InitArgs = struct {
    /// Name of the ringbuffer
    name: []const u8,
    /// Directory in which the ringbuffer will be created. This should be a ramfs (either tmpfs or hugetlbfs)
    dir: []const u8 = "/dev/shm",
};

const InitError = error{
    /// The ringbuffer name is too long
    NameTooLong,
    /// Trying to open a ringbuffer created by a Producer with a different version
    UnsupportedVersion,
    /// The ringbuffer should only be created in a ramfs: either tmpfs or hugetlbfs
    NotARamFs,
    /// It took too long to try to open the ringbuffer (is the producer alive?)
    Timeout,
};

const IOError = error{
    /// The ringbuffer is empty and the producer closed it
    Eof,
    /// There is nothing more to read at the moment
    Empty,
};

pub fn init(args: InitArgs) !Consumer {
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

    // Open the file backing the shared memory
    const fd = try errnocall(libc.openat, .{
        dirfd,
        &try z(args.name),
        libc.O_CLOEXEC | libc.O_RDWR,
        @as(libc.mode_t, 0o600),
    });
    defer errnocall_nr(libc.close, .{fd}) catch unreachable;

    // Retrieve the page size of the underlying ramfs
    var statfsbuf: libc.struct_statfs = undefined;
    try errnocall_nr(libc.fstatfs, .{ dirfd, &statfsbuf });
    switch (statfsbuf.f_type) {
        libc.MAGIC.TMPFS, libc.MAGIC.HUGETLBFS => {},
        else => return InitError.NotARamFs,
    }
    const page_size = statfsbuf.f_bsize;

    const capa: u64 = @intCast((try std.posix.fstat(fd)).size - @as(i64, @intCast(page_size)));

    const hugetlb_flags: c_int = switch (page_size) {
        4 * 1024 => 0,
        2 * 1024 * 1024 => libc.MAP_HUGE_2MB,
        1 * 1024 * 1024 * 1024 => libc.MAP_HUGETLB | libc.MAP_HUGE_1GB,
        else => unreachable,
    };

    // Map a block of contiguous virtual memory for:
    // - 1 whole page for the header
    // - N pages for the actual ringbuffer
    // - N pages for a identical mapping of the ringbuffer
    const mem = (try errnocall(libc.mmap, .{
        null,
        capa * 2 + page_size,
        libc.PROT_NONE,
        libc.MAP_ANONYMOUS | libc.MAP_PRIVATE | hugetlb_flags,
        -1,
        0,
    })).?;

    // Map the first page for the header
    try errnocall_nr(libc.mmap, .{
        mem,
        page_size,
        libc.PROT_READ | libc.PROT_WRITE,
        libc.MAP_FIXED | libc.MAP_SHARED | hugetlb_flags,
        fd,
        0,
    });

    // Map the N consecutive pages for the actual ringbuffer
    try errnocall_nr(libc.mmap, .{
        @as(*anyopaque, @ptrFromInt(@intFromPtr(mem) + page_size)),
        capa,
        libc.PROT_READ,
        libc.MAP_FIXED | libc.MAP_SHARED | hugetlb_flags,
        fd,
        @as(c_long, @intCast(page_size)),
    });

    // Map the N consecutive pages for an identical mapping of the previous region
    try errnocall_nr(libc.mmap, .{
        @as(*anyopaque, @ptrFromInt(@intFromPtr(mem) + page_size + capa)),
        capa,
        libc.PROT_READ,
        libc.MAP_FIXED | libc.MAP_SHARED,
        fd,
        @as(c_long, @intCast(page_size)),
    });
    const header: *Header = @as(*Header, @ptrCast(@alignCast(mem)));
    const data: []const u8 = @as([*]u8, @ptrFromInt(@intFromPtr(mem) + page_size))[0 .. capa * 2];

    // Fill in the shared memory with the structure of an empty ringbuffer
    if (header.version != QUEUE_VERSION) {
        return error.UnsupportedVersion;
    }

    return Consumer{
        .header = header,
        .data = data,
        .local_head = @atomicLoad(u64, &header.head, .acquire),
        .local_mask = header.capacity - 1,
        .local_capacity = header.capacity,
    };
}

/// Block while trying to open the ringbuffer, this is useful if you cannot guarantee that the
/// consumer will try to open the ringbuffer after the producer
pub fn initBlock(timeout_ms: u64, args: InitArgs) !Consumer {
    const start_time = std.time.milliTimestamp();
    return blk: while (true) {
        break :blk Consumer.init(args) catch {
            if (std.time.milliTimestamp() - start_time > timeout_ms) {
                return InitError.Timeout;
            }
            std.Thread.sleep(1 * std.time.ns_per_ms);
            continue;
        };
    };
}

pub fn deinit(self: *Consumer) !void {
    try errnocall_nr(libc.munmap, .{ self.header, self.header.page_size + self.header.capacity * 2 });
}

fn mask(self: Consumer, index: u64) u64 {
    return index & self.local_mask;
}

/// Ringbuffer actual capacity
pub fn capacity(self: Consumer) u64 {
    return self.local_capacity;
}

/// Is there any free space left in the ringbuffer
pub fn full(self: Consumer) bool {
    const head = @atomicLoad(u64, &self.header.head, .acquire);
    const tail = @atomicLoad(u64, &self.header.tail, .monotonic);

    return self.local_capacity == head -% tail;
}

/// Is there any unread data in the ringbuffer
pub fn empty(self: Consumer) bool {
    const head = @atomicLoad(u64, &self.header.head, .acquire);
    const tail = @atomicLoad(u64, &self.header.tail, .monotonic);

    return head == tail;
}

/// How much space is used in the ringbuffer
pub fn used(self: Consumer) u64 {
    const head = @atomicLoad(u64, &self.header.head, .acquire);
    const tail = @atomicLoad(u64, &self.header.tail, .monotonic);

    return head -% tail;
}

/// How much space is free in the ringbuffer
pub fn free(self: Consumer) u64 {
    const head = @atomicLoad(u64, &self.header.head, .acquire);
    const tail = @atomicLoad(u64, &self.header.tail, .monotonic);

    return self.local_capacity -% (head -% tail);
}

/// The producer closed its end of the ringbuffer
pub fn eof(self: Consumer) bool {
    return @atomicLoad(u64, &self.header.eof, .acquire) != 0;
}

/// Pop as much data as possible from the ringbuffer
pub fn pop(self: *Consumer) ![]const u8 {
    const tail = @atomicLoad(u64, &self.header.tail, .monotonic);
    var size = self.local_head -% tail;
    if (size == 0) {
        self.local_head = @atomicLoad(u64, &self.header.head, .acquire);
        size = self.local_head -% tail;
        if (size == 0) {
            if (self.eof()) {
                @branchHint(.cold);
                return error.Eof;
            } else {
                return error.Empty;
            }
        }
    }

    return self.data[self.mask(tail) .. self.mask(tail) +% size];
}

/// Commit the read data to the ringbuffer
pub fn commit(self: *Consumer, size: u64) void {
    const tail = @atomicLoad(u64, &self.header.tail, .monotonic);
    @atomicStore(u64, &self.header.tail, tail +% size, .release);
}

test "pop" {
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

    try std.testing.expectEqual(4096, c.capacity());
    try std.testing.expectEqual(false, c.full());
    try std.testing.expectEqual(true, c.empty());
    try std.testing.expectEqual(0, c.used());
    try std.testing.expectEqual(4096, c.free());

    const data_to_write = try p.push(10);
    @memset(data_to_write, 0xFF);
    p.commit(10);

    try std.testing.expectEqual(4096, c.capacity());
    try std.testing.expectEqual(false, c.full());
    try std.testing.expectEqual(false, c.empty());
    try std.testing.expectEqual(10, c.used());
    try std.testing.expectEqual(4086, c.free());

    const bytes = try c.pop();

    try std.testing.expectEqual(4096, c.capacity());
    try std.testing.expectEqual(false, c.full());
    try std.testing.expectEqual(false, c.empty());
    try std.testing.expectEqual(10, c.used());
    try std.testing.expectEqual(4086, c.free());

    c.commit(bytes.len);

    try std.testing.expectEqual(4096, c.capacity());
    try std.testing.expectEqual(false, c.full());
    try std.testing.expectEqual(true, c.empty());
    try std.testing.expectEqual(0, c.used());
    try std.testing.expectEqual(4096, c.free());
}
