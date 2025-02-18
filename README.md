# ezqueue

High performance single-producer / single-consumer (SPSC) queue in Zig,
optimized for low-latency and high throughput.

## Features

- Lock-free bounded queue (implemented as a ring-buffer)
- Very low latency (900M+ ops/s)
- Ideal for real-time scenarios
- No fixed block size, push any buffer of bytes of any size (though aligned
  loads and stores will perform better)
- Natively supports zero-copy with 2 stage reserve/commit on push and pop. This
  is ideal for I/O scenarios where you want to reserve space upfront for an
  incoming message, but only commit the bytes actually used. Conversely, you can
  eagerly parse the received messages from the queue and only mark as read a
  portion of it.
- Zero copy by default, data is reserved inside the queue so that you can write
  directly to it, and data can be read directly from it.
- The internal ring-buffer is mapped two times to allow contiguous wrap-around.
  This means you will get, from a single `pop()`, a contiguous buffer of bytes
  even if the data wrapped from the end to the beginning of the ring-buffer.
- Native support of huge pages, just mount a 2MB/1GB `hugetlbfs` and point the
  queue to use it

## Caveats

- Built for x86_64, may not work on other architectures
- Built for Linux, will not work on other operating systems
- Trades memory consumption in favor of performance by aggressively
  page-aligning and L1d cache-line aligning internal structures

## Implementation details

- Power-of-two queue capacity is mandatory, this avoids the use of expensive
  modulo operations, and allows for a free-rolling read/write indices
- Thread-local cache of read/write indices to avoid expensive acquire memory barriers

## Benchmark: ops/s

Producer and consumer are pinned on different cores, 10M (aligned) integers are
pushed and popped. _The queue achieves 900+ millions operations per second._

    consumer:throughput = 1000.000 Mm/s
    producer:throughput = 909.091 Mm/s

## Benchmark: loading a file from the disk to the queue

Producer and consumer are pinned on different cores, a 12GB file is read and
pushed to the queue while the consumer pops it.
_SSD maximum theorical throughput is reached (NVME Samsung 980 PRO on ext4)_

    producer:read count = x196
    producer:read size = 12461 MB
    producer:read throughput = 5.938 GB/s
    producer:elapsed time = 2021 ms
    consumer:read count = 195
    consumer:read size = 12461 MB
    consumer:spins = 4490454767

## Usage: Producer

Since there is a single producer, we do not need to copy data in and out of the
queue, instead we can directly reserve contiguous space inside the queue and
write there directly. This allows zero-copy write operations.

For instance, you can reserve 4k of contiguous space in the queue, and use that
for a `read()` call without temporary buffers or `memcpy`.

    // Create a producer
    var p = try Producer.init(.{
        .dir = "/dev/shm",
        .name = "ezqueue",
        .capacity = QUEUE_SIZE,
    });
    defer p.deinit() catch unreachable;

    var count: u64 = 0;
    while (count < 10000000) {
        // Reserve 8 bytes to write, spin if they are not available
        const bytes = p.push(8) catch continue;
        // Cast the 8 bytes to a u64
        const num: *align(1) u64 = @ptrCast(bytes.ptr);
        num.* = 0x0102030405060708;
        // Commit the 8 bytes so consumers can pop them
        p.commit(8);

        count += 1;
    }

## Usage: Consumer

Since there is a single consumer, we do not need to know in advance how much
data we want to pop. Instead, we just pop everything and later commit only the
amount of bytes we want to mark as read. This allows zero-copy reads.

For instance, you can have your parser directly read from the queue, commit
what you were able to parse, and start from there at the next iteration,
without any temporary buffers or `memcpy`.

The internal ring-buffer wraps around itself, meaning you will _always_ get a
single, contiguous memory buffer from `pop()`, even when data is split between
the end and the beginning of the ring-buffer.

Notice that `pop()` does not require a size, it will return a slice with all
the available data. This is essentially a free operation since no copy happens
here, you can then commit to pop only what you used.

    // Create a consumer, allow blocking for 1s (1000ms) to let the producer create
    // the queue
    var c = try Consumer.initBlock(1000, .{
        .name = "ezqueue",
        .dir = dir,
    });
    defer c.deinit() catch unreachable;

    var count: u64 = 0;
    while (count < 10000000) {
        // Pop everything that is available in the queue
        const bytes = c.pop() catch |err| switch (err) {
            error.Empty => continue, // Queue is empty, spin until there is something
            error.Eof => break,      // Queue is empty and producer is finished, stop trying
        };
        // Cast the first 8 bytes to a u64 and read it
        const num_ptr: *align(1) const u64 = @ptrCast(bytes.ptr);
        _ = num_ptr.*;
        // Commit 8 bytes from the received buffer as being read
        c.commit(8);

        count += 1;
    }

## Author

- Aurelien Vallee <aurelien.vallee@prontonmail.com>
