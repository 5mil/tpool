const compat = @import("compat.zig");
const std = @import("std");
const tls = @import("tls.zig");
const work = @import("work.zig");

const Job = struct {
    id: [32]u8 = @splat(0),
    id_len: usize = 0,
    prev: [64]u8 = @splat(0),
    coinb1: [1600]u8 = @splat(0),
    coinb1_len: usize = 0,
    coinb2: [1600]u8 = @splat(0),
    coinb2_len: usize = 0,
    branch: [16][32]u8 = undefined,
    branch_n: usize = 0,
    version: [8]u8 = @splat(0),
    nbits: [8]u8 = @splat(0),
    ntime: [8]u8 = @splat(0),
    ready: bool = false,
};

fn put(dst: []u8, src: []const u8) usize {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

fn quotes(line: []const u8, out: [][]const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len and n < out.len) : (i += 1) {
        if (line[i] != '"') continue;
        const end = std.mem.indexOfScalarPos(u8, line, i + 1, '"') orelse break;
        out[n] = line[i + 1 .. end];
        n += 1;
        i = end;
    }
    return n;
}

fn takeJob(line: []const u8, job: *Job) bool {
    var q: [24][]const u8 = undefined;
    const n = quotes(line, &q);
    var from: usize = 0;
    while (from < n and !std.mem.eql(u8, q[from], "mining.notify")) from += 1;
    if (from + 1 >= n) return false;
    var rest = q[from + 1 .. n];
    if (rest.len > 0 and std.mem.eql(u8, rest[0], "params")) rest = rest[1..];
    if (rest.len < 7 or rest[1].len < 64) return false;
    job.id_len = put(&job.id, rest[0]);
    @memcpy(job.prev[0..64], rest[1][0..64]);
    job.coinb1_len = put(&job.coinb1, rest[2]);
    job.coinb2_len = put(&job.coinb2, rest[3]);
    job.branch_n = 0;
    var b: usize = 4;
    while (b + 3 < rest.len and job.branch_n < job.branch.len) : (b += 1) {
        var raw: [32]u8 = undefined;
        const got = work.hexDecode(&raw, rest[b]) orelse break;
        if (got.len != 32) break;
        job.branch[job.branch_n] = raw;
        job.branch_n += 1;
    }
    const version = rest[rest.len - 3];
    const nbits = rest[rest.len - 2];
    const ntime = rest[rest.len - 1];
    @memcpy(job.version[0..@min(8, version.len)], version[0..@min(8, version.len)]);
    @memcpy(job.nbits[0..@min(8, nbits.len)], nbits[0..@min(8, nbits.len)]);
    @memcpy(job.ntime[0..@min(8, ntime.len)], ntime[0..@min(8, ntime.len)]);
    job.ready = job.coinb1_len > 0 and nbits.len >= 8;
    return job.ready;
}

fn takeEn1(line: []const u8, out: []u8) usize {
    var q: [12][]const u8 = undefined;
    const n = quotes(line, &q);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const item = q[i];
        if (item.len < 4 or item.len > 16 or item.len % 2 != 0) continue;
        var hex = true;
        for (item) |c| {
            if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) hex = false;
        }
        if (!hex) continue;
        return put(out, item);
    }
    return 0;
}

const Link = struct {
    stream: compat.net.Stream,
    secure: ?*tls.Session = null,
    acc: [8192]u8 = undefined,
    held: usize = 0,

    fn writeAll(self: *Link, data: []const u8) !void {
        if (self.secure) |s| return s.writeAll(data);
        return self.stream.writeAll(data);
    }

    fn readLine(self: *Link, out: []u8) ?usize {
        while (std.mem.indexOfScalar(u8, self.acc[0..self.held], '\n') == null) {
            if (self.held + 64 >= self.acc.len) return null;
            const n = if (self.secure) |s|
                s.read(self.acc[self.held..]) catch return null
            else
                self.stream.read(self.acc[self.held..]) catch return null;
            if (n == 0) return null;
            self.held += n;
        }
        const rel = std.mem.indexOfScalar(u8, self.acc[0..self.held], '\n').?;
        var end = @min(out.len, rel);
        @memcpy(out[0..end], self.acc[0..end]);
        if (end > 0 and out[end - 1] == '\r') end -= 1;
        const rest = rel + 1;
        std.mem.copyForwards(u8, self.acc[0 .. self.held - rest], self.acc[rest..self.held]);
        self.held -= rest;
        return end;
    }
};

fn grind(alloc: std.mem.Allocator, algo: []const u8, job: Job, en1: []const u8, en2: []const u8, diff: u32) ?[8]u8 {
    var nonce: u32 = 0;
    while (nonce < 200000) : (nonce += 1) {
        var nh: [8]u8 = undefined;
        const ns = std.fmt.bufPrint(&nh, "{x:0>8}", .{nonce}) catch continue;
        const checked = work.check(alloc, algo, job.version[0..8], job.prev[0..64], job.coinb1[0..job.coinb1_len], en1, en2, job.coinb2[0..job.coinb2_len], job.branch[0..job.branch_n], job.ntime[0..8], job.nbits[0..8], ns, diff, true);
        if (checked.verdict == .block) return nh;
        if (checked.verdict == .share and nonce == 0) {}
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    compat.bind(init);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 3333;
    var worker: []const u8 = "SteveCaseFan.rig1";
    var algo: []const u8 = "sha256d";
    var use_tls = false;
    var once = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--host")) host = args.next() orelse host;
        if (std.mem.eql(u8, arg, "--port")) port = std.fmt.parseInt(u16, args.next() orelse "3333", 10) catch 3333;
        if (std.mem.eql(u8, arg, "--worker")) worker = args.next() orelse worker;
        if (std.mem.eql(u8, arg, "--algo")) algo = args.next() orelse algo;
        if (std.mem.eql(u8, arg, "--tls")) use_tls = true;
        if (std.mem.eql(u8, arg, "--once")) once = true;
    }
    std.debug.print("miner {s} -> {s}:{d} as {s}{s}\n", .{ algo, host, port, worker, if (use_tls) " tls" else "" });
    const addr = try compat.net.Address.parseIp4(host, port);
    const stream = try compat.net.tcpConnectToAddress(addr);
    var session: tls.Session = undefined;
    var link = Link{ .stream = stream };
    if (use_tls) {
        session = tls.connect(stream) catch {
            std.debug.print("tls failed: {s}\n", .{tls.reasonText()});
            return error.Tls;
        };
        link.secure = &session;
    }
    var buf: [2048]u8 = undefined;
    const sub = try std.fmt.bufPrint(&buf, "{{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"thimble-miner/0.3 cpu\"]}}\n", .{});
    try link.writeAll(sub);
    const n = link.readLine(&buf) orelse return error.NoReply;
    std.debug.print("subscribe: {s}\n", .{buf[0..n]});
    var en1_buf: [16]u8 = undefined;
    const en1_len = takeEn1(buf[0..n], &en1_buf);
    if (en1_len == 0) return error.NoExtranonce;
    const auth = try std.fmt.bufPrint(&buf, "{{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"{s}\",\"x\"]}}\n", .{worker});
    try link.writeAll(auth);
    var diff: u32 = 1;
    var job = Job{};
    var found: usize = 0;
    while (found < 4) {
        const got = link.readLine(&buf) orelse return error.Closed;
        const line = buf[0..got];
        if (std.mem.indexOf(u8, line, "mining.set_difficulty") != null) {
            if (std.mem.indexOf(u8, line, "\"params\":[")) |at| {
                diff = std.fmt.parseInt(u32, line[at + 10 .. std.mem.indexOfScalarPos(u8, line, at + 10, ']') orelse at + 10], 10) catch diff;
            }
            std.debug.print("difficulty {d}\n", .{diff});
            continue;
        }
        if (std.mem.indexOf(u8, line, "mining.notify") != null) {
            std.debug.print("notify raw {d} bytes\n", .{line.len});
            if (compat.fs.cwd().createFile("/tmp/notify.txt", .{})) |f| {
                f.writeAll(line) catch {};
                f.close();
            } else |_| {}
            if (!takeJob(line, &job)) {
                std.debug.print("notify did not parse\n", .{});
                continue;
            }
            std.debug.print("job {s} height-bits {s}\n", .{ job.id[0..job.id_len], job.nbits[0..8] });
            const nonce = grind(init.gpa, algo, job, en1_buf[0..en1_len], "00000000", diff) orelse {
                std.debug.print("no nonce in 200000\n", .{});
                continue;
            };
            var submit: [240]u8 = undefined;
            const msg = try std.fmt.bufPrint(&submit, "{{\"id\":3,\"method\":\"mining.submit\",\"params\":[\"{s}\",\"{s}\",\"00000000\",\"{s}\",\"{s}\"]}}\n", .{ worker, job.id[0..job.id_len], job.ntime[0..8], nonce });
            try link.writeAll(msg);
            while (true) {
                const reply_n = link.readLine(&buf) orelse return error.NoSubmitReply;
                const reply = buf[0..reply_n];
                if (std.mem.indexOf(u8, reply, "\"id\":3") != null or std.mem.indexOf(u8, reply, "\"id\": 3") != null) {
                    std.debug.print("submit {s}: {s}\n", .{ nonce, reply });
                    break;
                }
                std.debug.print("skip: {s}\n", .{reply});
            }
            found += 1;
            if (once) return;
            continue;
        }
        if (std.mem.indexOf(u8, line, "\"result\"") != null) std.debug.print("reply: {s}\n", .{line});
    }
}
