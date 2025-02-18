const std = @import("std");
const maxInt = std.math.maxInt;

const c = @cImport({
    @cDefine("_GNU_SOURCE", {});
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("limits.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("time.h");
    @cInclude("sched.h");

    @cInclude("sys/vfs.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/statfs.h");
    @cInclude("sys/uio.h");
    @cInclude("sys/mman.h");
    @cUndef("_GNU_SOURCE");
});

pub usingnamespace c;

const ReturnType = @import("meta.zig").ReturnType;

/// Errno as Zig error codes
pub const Errno = error{
    // zig fmt: off
    EPERM, ENOENT, ESRCH, EINTR, EIO, ENXIO, E2BIG, ENOEXEC, EBADF, ECHILD, EAGAIN, ENOMEM, EACCES,
    EFAULT, ENOTBLK, EBUSY, EEXIST, EXDEV, ENODEV, ENOTDIR, EISDIR, EINVAL, ENFILE, EMFILE, ENOTTY,
    ETXTBSY, EFBIG, ENOSPC, ESPIPE, EROFS, EMLINK, EPIPE, EDOM, ERANGE, EDEADLOCK, ENAMETOOLONG,
    ENOLCK, ENOSYS, ENOTEMPTY, ELOOP, ENOMSG, EIDRM, ECHRNG, EL2NSYNC, EL3HLT, EL3RST, ELNRNG,
    EUNATCH, ENOCSI, EL2HLT, EBADE, EBADR, EXFULL, ENOANO, EBADRQC, EBADSLT, EBFONT, ENOSTR,
    ENODATA, ETIME, ENOSR, ENONET, ENOPKG, EREMOTE, ENOLINK, EADV, ESRMNT, ECOMM, EPROTO, EMULTIHOP,
    EDOTDOT, EBADMSG, EOVERFLOW, ENOTUNIQ, EBADFD, EREMCHG, ELIBACC, ELIBBAD, ELIBSCN, ELIBMAX,
    ELIBEXEC, EILSEQ, ERESTART, ESTRPIPE, EUSERS, ENOTSOCK, EDESTADDRREQ, EMSGSIZE, EPROTOTYPE,
    ENOPROTOOPT, EPROTONOSUPPORT, ESOCKTNOSUPPORT, EOPNOTSUPP, EPFNOSUPPORT, EAFNOSUPPORT, EADDRINUSE,
    EADDRNOTAVAIL, ENETDOWN, ENETUNREACH, ENETRESET, ECONNABORTED, ECONNRESET, ENOBUFS, EISCONN,
    ENOTCONN, ESHUTDOWN, ETOOMANYREFS, ETIMEDOUT, ECONNREFUSED, EHOSTDOWN, EHOSTUNREACH, EALREADY,
    EINPROGRESS, ESTALE, EUCLEAN, ENOTNAM, ENAVAIL, EISNAM, EREMOTEIO, EDQUOT, ENOMEDIUM, EMEDIUMTYPE,
    ECANCELED, ENOKEY, EKEYEXPIRED, EKEYREVOKED, EKEYREJECTED, EOWNERDEAD, ENOTRECOVERABLE, ERFKILL,
    // zig fmt: on
};

/// Map linux errno numbers to Zig error codes
pub fn errnoError(errno: c_int) Errno {
    return switch (errno) {
        // zig fmt: off
          1 => return error.EPERM,             2 => return error.ENOENT,              3 => return error.ESRCH,
          4 => return error.EINTR,             5 => return error.EIO,                 6 => return error.ENXIO,
          7 => return error.E2BIG,             8 => return error.ENOEXEC,             9 => return error.EBADF,
         10 => return error.ECHILD,           11 => return error.EAGAIN,             12 => return error.ENOMEM,
         13 => return error.EACCES,           14 => return error.EFAULT,             15 => return error.ENOTBLK,
         16 => return error.EBUSY,            17 => return error.EEXIST,             18 => return error.EXDEV,
         19 => return error.ENODEV,           20 => return error.ENOTDIR,            21 => return error.EISDIR,
         22 => return error.EINVAL,           23 => return error.ENFILE,             24 => return error.EMFILE,
         25 => return error.ENOTTY,           26 => return error.ETXTBSY,            27 => return error.EFBIG,
         28 => return error.ENOSPC,           29 => return error.ESPIPE,             30 => return error.EROFS,
         31 => return error.EMLINK,           32 => return error.EPIPE,              33 => return error.EDOM,
         34 => return error.ERANGE,           35 => return error.EDEADLOCK,          36 => return error.ENAMETOOLONG,
         37 => return error.ENOLCK,           38 => return error.ENOSYS,             39 => return error.ENOTEMPTY,
         40 => return error.ELOOP,            42 => return error.ENOMSG,             43 => return error.EIDRM,
         44 => return error.ECHRNG,           45 => return error.EL2NSYNC,           46 => return error.EL3HLT,
         47 => return error.EL3RST,           48 => return error.ELNRNG,             49 => return error.EUNATCH,
         50 => return error.ENOCSI,           51 => return error.EL2HLT,             52 => return error.EBADE,
         53 => return error.EBADR,            54 => return error.EXFULL,             55 => return error.ENOANO,
         56 => return error.EBADRQC,          57 => return error.EBADSLT,            59 => return error.EBFONT,
         60 => return error.ENOSTR,           61 => return error.ENODATA,            62 => return error.ETIME,
         63 => return error.ENOSR,            64 => return error.ENONET,             65 => return error.ENOPKG,
         66 => return error.EREMOTE,          67 => return error.ENOLINK,            68 => return error.EADV,
         69 => return error.ESRMNT,           70 => return error.ECOMM,              71 => return error.EPROTO,
         72 => return error.EMULTIHOP,        73 => return error.EDOTDOT,            74 => return error.EBADMSG,
         75 => return error.EOVERFLOW,        76 => return error.ENOTUNIQ,           77 => return error.EBADFD,
         78 => return error.EREMCHG,          79 => return error.ELIBACC,            80 => return error.ELIBBAD,
         81 => return error.ELIBSCN,          82 => return error.ELIBMAX,            83 => return error.ELIBEXEC,
         84 => return error.EILSEQ,           85 => return error.ERESTART,           86 => return error.ESTRPIPE,
         87 => return error.EUSERS,           88 => return error.ENOTSOCK,           89 => return error.EDESTADDRREQ,
         90 => return error.EMSGSIZE,         91 => return error.EPROTOTYPE,         92 => return error.ENOPROTOOPT,
         93 => return error.EPROTONOSUPPORT,  94 => return error.ESOCKTNOSUPPORT,    95 => return error.EOPNOTSUPP,
         96 => return error.EPFNOSUPPORT,     97 => return error.EAFNOSUPPORT,       98 => return error.EADDRINUSE,
         99 => return error.EADDRNOTAVAIL,   100 => return error.ENETDOWN,           101 => return error.ENETUNREACH,
        102 => return error.ENETRESET,       103 => return error.ECONNABORTED,       104 => return error.ECONNRESET,
        105 => return error.ENOBUFS,         106 => return error.EISCONN,            107 => return error.ENOTCONN,
        108 => return error.ESHUTDOWN,       109 => return error.ETOOMANYREFS,       110 => return error.ETIMEDOUT,
        111 => return error.ECONNREFUSED,    112 => return error.EHOSTDOWN,          113 => return error.EHOSTUNREACH,
        114 => return error.EALREADY,        115 => return error.EINPROGRESS,        116 => return error.ESTALE,
        117 => return error.EUCLEAN,         118 => return error.ENOTNAM,            119 => return error.ENAVAIL,
        120 => return error.EISNAM,          121 => return error.EREMOTEIO,          122 => return error.EDQUOT,
        123 => return error.ENOMEDIUM,       124 => return error.EMEDIUMTYPE,        125 => return error.ECANCELED,
        126 => return error.ENOKEY,          127 => return error.EKEYEXPIRED,        128 => return error.EKEYREVOKED,
        129 => return error.EKEYREJECTED,    130 => return error.EOWNERDEAD,         131 => return error.ENOTRECOVERABLE,
        132 => return error.ERFKILL,        else => unreachable,
        // zig fmt: on
    };
}

/// MAGIC numbers for various filesystems, used by statfs.f_type
/// From Linux UAPI at include/uapi/linux/magic.h
pub const MAGIC = struct {
    pub const HUGETLBFS = 0x958458f6;
    pub const TMPFS = 0x01021994;
};

/// Wrapper to call a "errno function": one that returns -1 on error and sets errno accordingly
/// (essentially syscalls and libc)
pub fn errnocall(func: anytype, args: anytype) Errno!ReturnType(func) {
    return while (true) {
        const rc = @call(.auto, func, args);
        const Sentinel: type = @Type(.{ .int = .{ .bits = @sizeOf(@TypeOf(rc)) * 8, .signedness = .unsigned } });
        const sentinel = maxInt(Sentinel);
        const rcc = switch (@typeInfo(@TypeOf(rc))) {
            .optional => @as(Sentinel, @intCast(@intFromPtr(rc))),
            else => @as(Sentinel, @bitCast(rc)),
        };
        const errno = c.__errno_location().*;
        if (rcc == sentinel) {
            switch (errno) {
                c.EINTR => continue,
                else => return errnoError(errno),
            }
        }
        break rc;
    };
}

/// Same as `errnocall` but do not return the result of the function call as it has no meaning
pub fn errnocall_nr(func: anytype, args: anytype) !void {
    _ = try errnocall(func, args);
}

/// Helper function to convert a []const u8 to a C string on the stack
pub const z = std.posix.toPosixPath;

pub const fd_t = std.os.linux.fd_t;
pub const pid_t = std.os.linux.pid_t;
