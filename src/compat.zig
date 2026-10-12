const std = @import("std");

pub var io: std.Io = undefined;
pub var gpa: std.mem.Allocator = std.heap.page_allocator;
pub var environ: *std.process.Environ.Map = undefined;

pub fn bind(init: std.process.Init) void {
    io = init.io;
    gpa = init.gpa;
    environ = init.environ_map;
}

pub fn getEnv(alloc: std.mem.Allocator, name: []const u8) ![]u8 {
    if (environ.get(name)) |value| {
        if (value.len > 0) return alloc.dupe(u8, value);
    }
    const saved = hostValue(name);
    if (saved.len == 0) return error.EnvironmentVariableNotFound;
    return alloc.dupe(u8, saved);
}

pub var host_fresh = false;
pub var force_setup = false;

var host_admin: [64]u8 = undefined;
var host_admin_len: usize = 0;
var host_pay: [24]u8 = undefined;
var host_pay_len: usize = 0;
var host_rpc: [160]u8 = undefined;
var host_rpc_len: usize = 0;
var host_up: [96]u8 = undefined;
var host_up_len: usize = 0;
var host_wallet: [80]u8 = undefined;
var host_wallet_len: usize = 0;

pub fn adminText() []const u8 {
    return host_admin[0..host_admin_len];
}
pub fn payText() []const u8 {
    return host_pay[0..host_pay_len];
}
pub fn rpcText() []const u8 {
    return host_rpc[0..host_rpc_len];
}
pub fn upstreamText() []const u8 {
    return host_up[0..host_up_len];
}
pub fn walletText() []const u8 {
    return host_wallet[0..host_wallet_len];
}

fn hostValue(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "THIMBLE_ADMIN")) return adminText();
    if (std.mem.eql(u8, name, "THIMBLE_PAY_SATS")) return payText();
    if (std.mem.eql(u8, name, "THIMBLE_RPC")) return rpcText();
    if (std.mem.eql(u8, name, "THIMBLE_UPSTREAM")) return upstreamText();
    if (std.mem.eql(u8, name, "THIMBLE_WALLET")) return walletText();
    return "";
}

fn putHost(dst: []u8, len: *usize, src: []const u8) void {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    len.* = n;
}

pub fn hostFileExists() bool {
    fs.cwd().access("host.cfg", .{}) catch return false;
    return true;
}

fn applyLine(line: []const u8) void {
    if (line.len == 0 or line[0] == '#') return;
    const cut = std.mem.indexOfScalar(u8, line, '=') orelse return;
    const key = line[0..cut];
    const val = line[cut + 1 ..];
    if (std.mem.eql(u8, key, "admin")) putHost(&host_admin, &host_admin_len, val);
    if (std.mem.eql(u8, key, "pay_sats")) putHost(&host_pay, &host_pay_len, val);
    if (std.mem.eql(u8, key, "rpc")) putHost(&host_rpc, &host_rpc_len, val);
    if (std.mem.eql(u8, key, "upstream")) putHost(&host_up, &host_up_len, val);
    if (std.mem.eql(u8, key, "wallet")) putHost(&host_wallet, &host_wallet_len, val);
}

pub fn loadHostFile() void {
    const raw = fs.cwd().readFileAlloc(std.heap.page_allocator, "host.cfg", 1 << 16) catch return;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| applyLine(std.mem.trim(u8, line, " \r"));
}

pub fn writeHost(admin: []const u8, pay: []const u8, rpc: []const u8, upstream: []const u8, wallet: []const u8) void {
    var admin_buf: [64]u8 = undefined;
    var pay_buf: [24]u8 = undefined;
    var rpc_buf: [160]u8 = undefined;
    var up_buf: [96]u8 = undefined;
    var wallet_buf: [80]u8 = undefined;
    const an = @min(admin.len, admin_buf.len);
    const pn = @min(pay.len, pay_buf.len);
    const rn = @min(rpc.len, rpc_buf.len);
    const un = @min(upstream.len, up_buf.len);
    const wn = @min(wallet.len, wallet_buf.len);
    @memcpy(admin_buf[0..an], admin[0..an]);
    @memcpy(pay_buf[0..pn], pay[0..pn]);
    @memcpy(rpc_buf[0..rn], rpc[0..rn]);
    @memcpy(up_buf[0..un], upstream[0..un]);
    @memcpy(wallet_buf[0..wn], wallet[0..wn]);
    var file = fs.cwd().createFile("host.cfg.tmp", .{}) catch return;
    file.print("admin={s}\npay_sats={s}\nrpc={s}\nupstream={s}\nwallet={s}\n", .{ admin_buf[0..an], pay_buf[0..pn], rpc_buf[0..rn], up_buf[0..un], wallet_buf[0..wn] }) catch {
        file.close();
        return;
    };
    file.close();
    fs.cwd().rename("host.cfg.tmp", "host.cfg") catch return;
    putHost(&host_admin, &host_admin_len, admin_buf[0..an]);
    putHost(&host_pay, &host_pay_len, pay_buf[0..pn]);
    putHost(&host_rpc, &host_rpc_len, rpc_buf[0..rn]);
    putHost(&host_up, &host_up_len, up_buf[0..un]);
    putHost(&host_wallet, &host_wallet_len, wallet_buf[0..wn]);
}

fn makeAdmin(buf: *[16]u8) void {
    const ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    var x: u64 = @truncate(@as(u96, @bitCast(ns)));
    x ^= x >> 30;
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        buf[i] = hex[@intCast(x & 0xf)];
        x +%= 0x9E3779B97F4A7C15;
    }
}

pub fn ensureHost() void {
    if (hostFileExists()) {
        loadHostFile();
        return;
    }
    var admin: [16]u8 = undefined;
    makeAdmin(&admin);
    writeHost(&admin, "100000", "", "", "");
    host_fresh = true;
    if (comptime @import("builtin").os.tag != .windows) {
        std.debug.print("First start. Wrote host.cfg beside the program.\n", .{});
        std.debug.print("Admin token, shown once: {s}\n", .{&admin});
        std.debug.print("Pool ports stay closed until a module has a chain source.\n", .{});
        std.debug.print("Change the token with --setup, or edit host.cfg. The environment overrides the file.\n", .{});
    }
}

fn ask(in: File, buf: []u8) []const u8 {
    const n = in.read(buf) catch return "";
    return std.mem.trim(u8, buf[0..n], " \r\n");
}

pub fn promptSetup() void {
    if (comptime @import("builtin").os.tag == .windows) return;
    const in = File{ .inner = std.Io.File.stdin() };
    var buf: [180]u8 = undefined;
    const have = hostFileExists();
    if (have) loadHostFile();
    std.debug.print("\nThimble setup. Blank keeps the current value.\n", .{});
    std.debug.print("Admin token (8 or more characters): ", .{});
    const admin_in = ask(in, &buf);
    var admin_buf: [64]u8 = undefined;
    const admin = if (admin_in.len >= 8) admin_in else if (have and host_admin_len >= 8) adminText() else blk: {
        var gen: [16]u8 = undefined;
        makeAdmin(&gen);
        @memcpy(admin_buf[0..16], &gen);
        break :blk admin_buf[0..16];
    };
    var admin_len: usize = 16;
    if (@intFromPtr(admin.ptr) != @intFromPtr(&admin_buf)) {
        admin_len = @min(admin.len, admin_buf.len);
        @memcpy(admin_buf[0..admin_len], admin[0..admin_len]);
    }
    std.debug.print("Pay a balance at this many satoshis [100000]: ", .{});
    const pay_in = ask(in, &buf);
    const pay = if (pay_in.len > 0) pay_in else if (host_pay_len > 0) payText() else "100000";
    var pay_buf: [24]u8 = undefined;
    const pn = @min(pay.len, pay_buf.len);
    @memcpy(pay_buf[0..pn], pay[0..pn]);
    std.debug.print("Upstream pool host:port, or blank for none: ", .{});
    const up_in = ask(in, &buf);
    const up = if (up_in.len > 0) up_in else upstreamText();
    var up_buf: [96]u8 = undefined;
    const un = @min(up.len, up_buf.len);
    @memcpy(up_buf[0..un], up[0..un]);
    writeHost(admin_buf[0..admin_len], pay_buf[0..pn], rpcText(), up_buf[0..un], walletText());
    std.debug.print("Saved host.cfg. Admin length {d}. Pay at {s} sats.\n", .{ admin_len, pay_buf[0..pn] });
    if (un > 0) std.debug.print("Upstream is stored. Restart if the pool is already running.\n", .{});
}


pub const Mutex = struct {
    raw: std.atomic.Mutex = .unlocked,
    pub fn lock(self: *Mutex) void {
        while (!self.raw.tryLock()) std.atomic.spinLoopHint();
    }
    pub fn unlock(self: *Mutex) void {
        self.raw.unlock();
    }
};

pub const time = struct {
    pub fn timestamp() i64 {
        const now = std.Io.Timestamp.now(io, .real);
        return @intCast(@divFloor(now.nanoseconds, std.time.ns_per_s));
    }
    pub fn sleep(ns: u64) void {
        std.Io.sleep(io, .{ .nanoseconds = @intCast(ns) }, .real) catch {};
    }
};

pub const File = struct {
    inner: std.Io.File,

    pub fn close(self: File) void {
        self.inner.close(io);
    }
    pub fn writeAll(self: File, data: []const u8) !void {
        try self.inner.writeStreamingAll(io, data);
    }
    pub fn print(self: *File, comptime fmt: []const u8, args: anytype) !void {
        var buf: [4096]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch return error.NoSpaceLeft;
        try self.writeAll(text);
    }
    pub fn read(self: File, buf: []u8) !usize {
        var slices = [_][]u8{buf};
        return self.inner.readStreaming(io, &slices) catch |err| switch (err) {
            error.EndOfStream => 0,
            else => |e| return e,
        };
    }
    pub fn readToEndAlloc(self: File, alloc: std.mem.Allocator, max: usize) ![]u8 {
        var list = std.array_list.Managed(u8).init(alloc);
        var tmp: [4096]u8 = undefined;
        while (list.items.len < max) {
            const n = self.read(tmp[0..@min(tmp.len, max - list.items.len)]) catch |err| return err;
            if (n == 0) break;
            try list.appendSlice(tmp[0..n]);
        }
        return list.toOwnedSlice();
    }
};

pub const fs = struct {
    pub const path = struct {
        pub fn stem(p: []const u8) []const u8 {
            return std.Io.Dir.path.stem(p);
        }
    };
    pub const Dir = struct {
        pub fn createFile(_: Dir, name: []const u8, _: anytype) !File {
            return .{ .inner = try std.Io.Dir.cwd().createFile(io, name, .{}) };
        }
        pub fn openFile(_: Dir, name: []const u8, _: anytype) !File {
            return .{ .inner = try std.Io.Dir.cwd().openFile(io, name, .{}) };
        }
        pub fn readFileAlloc(_: Dir, alloc: std.mem.Allocator, name: []const u8, max: usize) ![]u8 {
            return std.Io.Dir.cwd().readFileAlloc(io, name, alloc, .limited(max));
        }
        pub fn rename(_: Dir, old: []const u8, new: []const u8) !void {
            const dir = std.Io.Dir.cwd();
            try dir.rename(old, dir, new, io);
        }
        pub fn access(_: Dir, name: []const u8, _: anytype) !void {
            try std.Io.Dir.cwd().access(io, name, .{});
        }
        pub fn makePath(_: Dir, name: []const u8) !void {
            try std.Io.Dir.cwd().createDirPath(io, name);
        }
        pub fn deleteTree(_: Dir, name: []const u8) !void {
            try std.Io.Dir.cwd().deleteTree(io, name);
        }
    };
    pub fn cwd() Dir {
        return .{};
    }
};

pub const net = struct {
    pub const Address = struct {
        inner: std.Io.net.IpAddress,
        pub fn parseIp4(text: []const u8, port: u16) !Address {
            return .{ .inner = try std.Io.net.IpAddress.parseIp4(text, port) };
        }
        pub fn listen(self: Address, _: anytype) !Server {
            return .{ .inner = try self.inner.listen(io, .{ .reuse_address = true }) };
        }
    };

    pub const Stream = struct {
        inner: std.Io.net.Stream,
        pub fn close(self: Stream) void {
            self.inner.close(io);
        }
        pub fn writeAll(self: Stream, bytes: []const u8) !void {
            var buf: [1024]u8 = undefined;
            var w = self.inner.writer(io, &buf);
            try w.interface.writeAll(bytes);
            try w.interface.flush();
        }
        pub fn read(self: *const Stream, buf: []u8) !usize {
            var slices = [_][]u8{buf};
            var control: [16]u8 align(std.Io.net.cmsg_align) = undefined;
            const result = try self.inner.readWithControl(io, &slices, &control);
            return result.data_len;
        }
        pub fn reader(self: *const Stream) Reader {
            return .{ .stream = self };
        }
    };

    pub const Reader = struct {
        stream: *const Stream,
        pub fn readAllAlloc(self: Reader, alloc: std.mem.Allocator, max: usize) ![]u8 {
            var list = std.array_list.Managed(u8).init(alloc);
            var tmp: [4096]u8 = undefined;
            while (list.items.len < max) {
                const n = self.stream.read(tmp[0..@min(tmp.len, max - list.items.len)]) catch break;
                if (n == 0) break;
                try list.appendSlice(tmp[0..n]);
            }
            return list.toOwnedSlice();
        }
    };

    pub const Server = struct {
        inner: std.Io.net.Server,
        pub const Connection = struct { stream: Stream };
        pub fn accept(self: *Server) !Connection {
            return .{ .stream = .{ .inner = try self.inner.accept(io) } };
        }
    };

    pub fn tcpConnectToAddress(addr: Address) !Stream {
        return .{ .inner = try addr.inner.connect(io, .{ .mode = .stream, .protocol = .tcp }) };
    }

    pub fn getAddressList(alloc: std.mem.Allocator, host: []const u8, port: u16) !AddressList {
        if (Address.parseIp4(host, port)) |addr| {
            const addrs = try alloc.alloc(Address, 1);
            addrs[0] = addr;
            return .{ .addrs = addrs, .alloc = alloc };
        } else |_| {}
        const name = std.Io.net.HostName.init(host) catch return error.UnknownHostName;
        var storage: [16]std.Io.net.HostName.LookupResult = undefined;
        var q = std.Io.Queue(std.Io.net.HostName.LookupResult).init(&storage);
        try name.lookup(io, &q, .{ .port = port });
        var tmp: [8]Address = undefined;
        var n: usize = 0;
        while (n < tmp.len) {
            const item = q.getOneUncancelable(io) catch break;
            switch (item) {
                .address => |a| {
                    tmp[n] = .{ .inner = a };
                    n += 1;
                },
                else => {},
            }
        }
        if (n == 0) return error.UnknownHostName;
        const addrs = try alloc.alloc(Address, n);
        @memcpy(addrs, tmp[0..n]);
        return .{ .addrs = addrs, .alloc = alloc };
    }

    pub fn connectHost(host: []const u8, port: u16) !Stream {
        const list = try getAddressList(std.heap.page_allocator, host, port);
        defer list.deinit();
        if (list.addrs.len == 0) return error.UnknownHostName;
        return try tcpConnectToAddress(list.addrs[0]);
    }

    pub const AddressList = struct {
        addrs: []Address,
        alloc: std.mem.Allocator,
        pub fn deinit(self: AddressList) void {
            self.alloc.free(self.addrs);
        }
    };
};

pub const Child = struct {
    argv: []const []const u8,
    stdout_behavior: Stdio = .Inherit,
    stderr_behavior: Stdio = .Inherit,
    stderr: ?File = null,
    stdout: ?File = null,
    inner: ?std.process.Child = null,
    create_no_window: bool = false,

    stderr_file: ?std.Io.File = null,
    stdout_file: ?std.Io.File = null,

    pub const Stdio = enum { Inherit, Ignore, Pipe };
    pub const Term = union(enum) { Exited: u32 };

    pub fn init(argv: []const []const u8, _: std.mem.Allocator) Child {
        return .{ .argv = argv };
    }

    fn stdio(kind: Stdio) std.process.SpawnOptions.StdIo {
        return switch (kind) {
            .Inherit => .inherit,
            .Ignore => .ignore,
            .Pipe => .pipe,
        };
    }

    pub fn spawn(self: *Child) !void {
        self.inner = try std.process.spawn(io, .{
            .argv = self.argv,
            .stdout = if (self.stdout_file) |f| .{ .file = f } else stdio(self.stdout_behavior),
            .stderr = if (self.stderr_file) |f| .{ .file = f } else stdio(self.stderr_behavior),
            .create_no_window = self.create_no_window,
        });
        if (self.inner.?.stdout) |out_file| self.stdout = .{ .inner = out_file };
        if (self.inner.?.stderr) |err_file| self.stderr = .{ .inner = err_file };
    }

    pub fn kill(self: *Child) void {
        if (self.inner) |*proc| proc.kill(io);
        self.inner = null;
    }

    pub fn wait(self: *Child) !Term {
        const term = try self.inner.?.wait(io);
        return switch (term) {
            .exited => |code| .{ .Exited = code },
            else => .{ .Exited = 1 },
        };
    }

    pub fn spawnAndWait(self: *Child) !Term {
        try self.spawn();
        return self.wait();
    }
};
