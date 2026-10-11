const compat = @import("compat.zig");
const std = @import("std");
const chain = @import("chain.zig");
const modules = @import("modules.zig");
const party = @import("party.zig");
const ops = @import("ops.zig");
const tls = @import("tls.zig");
const work = @import("work.zig");

pub const algos = [_][]const u8{ "sha256d", "scrypt", "ethash", "kawpow", "randomx", "yescrypt" };
pub const ports = [_]u16{ 3333, 3334, 3335, 3336, 3337, 3338 };

pub const Pool = struct {
    lock: compat.Mutex = .{},
    accepted: u64 = 0,
    rejected: u64 = 0,
    blocks: u64 = 0,
    workers: std.array_list.Managed(Worker),
    alloc: std.mem.Allocator,

    pub const Worker = struct {
        name: []u8,
        party: []u8,
        algo: []u8,
        device: []u8,
        threads: u32,
        agent: []u8,
        shares: u64 = 0,
        round: u64 = 0,
        seen: i64 = 0,
        diff: u32 = 1,
        balance: u64 = 0,
        immature: u64 = 0,
        hashrate: u64 = 0,
        window_diff: u64 = 0,
        window_at: i64 = 0,
        vardiff_n: u32 = 0,
    };

    pub fn init(alloc: std.mem.Allocator) Pool {
        return .{ .workers = std.array_list.Managed(Worker).init(alloc), .alloc = alloc };
    }

    pub fn statusJson(self: *Pool, alloc: std.mem.Allocator) ![]u8 {
        self.lock.lock();
        defer self.lock.unlock();
        var out = std.array_list.Managed(u8).init(alloc);
        try out.appendSlice("{\"coin\":");
        const cfg = compat.fs.cwd().readFileAlloc(alloc, "coin.cfg", 4096) catch "name=none\n";
        const name_at = std.mem.indexOf(u8, cfg, "name=") orelse 0;
        const name = if (name_at == 0 and !std.mem.startsWith(u8, cfg, "name=")) "none" else cfg[name_at + 5 .. std.mem.indexOfScalarPos(u8, cfg, name_at, '\n') orelse cfg.len];
        try out.print("\"{s}\",\"algos\":[\"sha256d\",\"scrypt\",\"ethash\",\"kawpow\",\"randomx\",\"yescrypt\"],\"ports\":{{\"sha256d\":3333,\"scrypt\":3334,\"ethash\":3335,\"kawpow\":3336,\"randomx\":3337,\"yescrypt\":3338}},\"accepted\":", .{name});
        try out.print("{d},\"rejected\":{d},\"party\":[", .{ self.accepted, self.rejected });
        var seen_party = std.array_list.Managed([]const u8).init(alloc);
        defer seen_party.deinit();
        var first_party = true;
        for (self.workers.items) |w| {
            var known = false;
            for (seen_party.items) |p| {
                if (std.mem.eql(u8, p, w.party)) known = true;
            }
            if (known) continue;
            try seen_party.append(w.party);
            var total: u64 = 0;
            for (self.workers.items) |m| {
                if (std.mem.eql(u8, m.party, w.party)) total += m.shares;
            }
            if (!first_party) try out.append(',');
            first_party = false;
            try out.print("{{\"name\":\"{s}\",\"shares\":{d}}}", .{ clean(w.party), total });
        }
        try out.appendSlice("],\"workers\":[");
        for (self.workers.items, 0..) |w, i| {
            if (i != 0) try out.append(',');
            try out.print("{{\"name\":\"{s}\",\"party\":\"{s}\",\"algo\":\"{s}\",\"device\":\"{s}\",\"threads\":{d},\"agent\":\"{s}\",\"shares\":{d},\"diff\":{d},\"hashrate\":{d},\"immature\":{d}}}", .{ clean(w.name), clean(w.party), clean(w.algo), clean(w.device), w.threads, clean(w.agent), w.shares, w.diff, w.hashrate, w.immature });
        }
        try out.appendSlice("]}");
        return out.toOwnedSlice();
    }
};

pub var pool: Pool = undefined;

pub fn reportText(alloc: std.mem.Allocator) ![]u8 {
    pool.lock.lock();
    defer pool.lock.unlock();
    var out = std.array_list.Managed(u8).init(alloc);
    var ports_on: [48]u8 = undefined;
    var pn: usize = 0;
    var seen: [8]u16 = undefined;
    var seen_n: usize = 0;
    for (modules.mods[0..modules.count]) |m| {
        if (!m.on) continue;
        var already = false;
        for (seen[0..seen_n]) |p| {
            if (p == m.port) already = true;
        }
        if (already) continue;
        if (seen_n < seen.len) {
            seen[seen_n] = m.port;
            seen_n += 1;
        }
        const piece = std.fmt.bufPrint(ports_on[pn..], "{d} ", .{m.port}) catch break;
        pn += piece.len;
    }
    if (pn == 0) {
        @memcpy(ports_on[0..4], "none");
        pn = 4;
    }
    try out.appendSlice("--- codebase ---\n");
    var stage_buf: [180]u8 = undefined;
    try out.print("{s}\n", .{chain.stageLine(&stage_buf)});
    try out.appendSlice("--- ports ---\n");
    try out.print("open  {s}\n", .{ports_on[0..pn]});
    var chain_buf: [200]u8 = undefined;
    try out.appendSlice("--- node ---\n");
    try out.print("{s}\n", .{chain.statusLine(&chain_buf)});
    var mod_buf: [2000]u8 = undefined;
    try out.appendSlice(modules.line(&mod_buf));
    try out.appendSlice("\n--- parties ---\n");
    const now = compat.time.timestamp();
    for (party.parties[0..party.count]) |*p| {
        var on: u16 = 0;
        for (pool.workers.items) |w| {
            if (std.mem.eql(u8, w.party, p.name[0..p.name_len]) and now - w.seen < 120) on += 1;
        }
        p.online = on;
    }
    var party_buf: [4000]u8 = undefined;
    try out.appendSlice(party.line(&party_buf));
    for (party.parties[0..party.count]) |p| {
        for (pool.workers.items) |w| {
            if (!std.mem.eql(u8, w.party, p.name[0..p.name_len])) continue;
            const live = now - w.seen < 120;
            try out.print("    {s}  round {d}  balance {d}  immature {d}  diff {d}  hash {d} H/s  {s}\n", .{ w.name, w.round, w.balance, w.immature, w.diff, w.hashrate, if (live) "online" else "idle" });
        }
    }
    try out.appendSlice("--- check ---\n");
    try out.print("{s}\n", .{ops.headline()});
    try out.appendSlice("--- totals ---\n");
    try out.print("accepted {d}   rejected {d}   blocks {d}   workers {d}\n", .{ pool.accepted, pool.rejected, pool.blocks, pool.workers.items.len });
    for (pool.workers.items) |w| {
        const live = compat.time.timestamp() - w.seen < 120;
        try out.print("  {s}  party {s}  round {d}  life {d}  hash {d} H/s  immature {d}  {s}  {s}\n", .{ w.name, w.party, w.round, w.shares, w.hashrate, w.immature, if (live) "online" else "idle", w.device });
    }
    return out.toOwnedSlice();
}

fn firstQuoted(line: []const u8) []const u8 {
    const mark = std.mem.indexOf(u8, line, "[\"") orelse return "";
    const end = std.mem.indexOfScalarPos(u8, line, mark + 2, '"') orelse return "";
    return line[mark + 2 .. end];
}

fn jsonString(line: []const u8, key: []const u8, out: []u8) []u8 {
    var pat: [32]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "\"{s}\":", .{key}) catch return out[0..0];
    const at = std.mem.indexOf(u8, line, p) orelse return out[0..0];
    var i = at + p.len;
    while (i < line.len and line[i] == ' ') i += 1;
    if (i >= line.len) return out[0..0];
    if (line[i] == '"') {
        i += 1;
        var n: usize = 0;
        while (i < line.len and line[i] != '"' and n + 1 < out.len) : (i += 1) {
            out[n] = line[i];
            n += 1;
        }
        return out[0..n];
    }
    var n: usize = 0;
    while (i < line.len and line[i] != ',' and line[i] != '}' and n + 1 < out.len) : (i += 1) {
        out[n] = line[i];
        n += 1;
    }
    return out[0..n];
}

fn clean(text: []const u8) []const u8 {
    for (text) |c| if (c == '"' or c == '\\' or c < 32) return "bad";
    return text;
}

fn partyOf(name: []const u8) []const u8 {
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return "lobby";
    if (dot == 0) return "lobby";
    return name[0..dot];
}

fn partyAndSecret(line: []const u8, worker: []const u8, name_out: []u8, secret_out: []u8) struct { name: []const u8, secret: []const u8 } {
    var pass: []const u8 = "";
    const mark = std.mem.indexOf(u8, line, "[\"") orelse 0;
    var i: usize = mark;
    var nq: usize = 0;
    while (i + 1 < line.len) : (i += 1) {
        if (line[i] != '"') continue;
        const end = std.mem.indexOfScalarPos(u8, line, i + 1, '"') orelse break;
        nq += 1;
        if (nq == 2) {
            pass = line[i + 1 .. end];
            break;
        }
        i = end;
    }
    if (std.mem.startsWith(u8, pass, "p=")) pass = pass[2..];
    if (pass.len == 0 or std.mem.eql(u8, pass, "x")) {
        const pname = partyOf(worker);
        const n = @min(name_out.len, pname.len);
        @memcpy(name_out[0..n], pname);
        return .{ .name = name_out[0..n], .secret = secret_out[0..0] };
    }
    if (std.mem.indexOfScalar(u8, pass, ':')) |colon| {
        const n = @min(name_out.len, colon);
        @memcpy(name_out[0..n], pass[0..colon]);
        const secret = pass[colon + 1 ..];
        const sn = @min(secret_out.len, secret.len);
        @memcpy(secret_out[0..sn], secret);
        return .{ .name = name_out[0..n], .secret = secret_out[0..sn] };
    }
    const n = @min(name_out.len, pass.len);
    @memcpy(name_out[0..n], pass);
    return .{ .name = name_out[0..n], .secret = secret_out[0..0] };
}

fn loadParty() void {
    const raw = compat.fs.cwd().readFileAlloc(pool.alloc, "party.db", 1 << 20) catch return;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (line.len < 3) continue;
        var parts = std.mem.splitScalar(u8, line, '\t');
        const name = parts.next() orelse continue;
        const pname = parts.next() orelse "lobby";
        const algo = parts.next() orelse "sha256d";
        const shares = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        const round = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        const balance = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        const diff = std.fmt.parseInt(u32, parts.next() orelse "1", 10) catch 1;
        pool.accepted += shares;
        pool.workers.append(.{
            .name = pool.alloc.dupe(u8, name) catch "",
            .party = pool.alloc.dupe(u8, pname) catch "",
            .algo = pool.alloc.dupe(u8, algo) catch "",
            .device = pool.alloc.dupe(u8, "saved") catch "",
            .threads = 0,
            .agent = pool.alloc.dupe(u8, "disk") catch "",
            .shares = shares,
            .round = round,
            .balance = balance,
            .diff = if (diff == 0) 1 else diff,
        }) catch {};
        party.of(pname).round += round;
    }
    loadDue();
}

fn saveParty() void {
    var buf = std.array_list.Managed(u8).init(pool.alloc);
    defer buf.deinit();
    for (pool.workers.items) |w| {
        buf.print("{s}\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\n", .{ w.name, w.party, w.algo, w.shares, w.round, w.balance, w.diff }) catch return;
    }
    const tmp = "party.db.tmp";
    var file = compat.fs.cwd().createFile(tmp, .{}) catch return;
    file.writeAll(buf.items) catch {
        file.close();
        return;
    };
    file.close();
    compat.fs.cwd().rename(tmp, "party.db") catch {
        var direct = compat.fs.cwd().createFile("party.db", .{}) catch return;
        defer direct.close();
        direct.writeAll(buf.items) catch return;
    };
    party.save(pool.alloc);
}

const Link = struct {
    stream: compat.net.Stream,
    secure: ?*tls.Session = null,
    acc: [4096]u8 = undefined,
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

fn serve(conn: compat.net.Server.Connection, algo: []const u8, port: u16) void {
    var link = Link{ .stream = conn.stream };
    serveLink(&link, algo, port);
    conn.stream.close();
}

fn serveTls(conn: compat.net.Server.Connection, algo: []const u8, port: u16) void {
    var session = tls.accept(conn.stream) catch {
        conn.stream.close();
        return;
    };
    var link = Link{ .stream = conn.stream, .secure = &session };
    serveLink(&link, algo, port);
    conn.stream.close();
}

fn serveLink(link: *Link, algo: []const u8, port: u16) void {
    var buf: [2048]u8 = undefined;
    var worker: [80]u8 = undefined;
    var worker_len: usize = 0;
    var device: [48]u8 = undefined;
    var device_len: usize = 11;
    const threads: u32 = 0;
    var agent: [48]u8 = undefined;
    var agent_len: usize = 7;
    @memcpy(device[0..11], "asic-or-gpu");
    @memcpy(agent[0..7], "stratum");
    var authorized = false;
    var diff: u32 = if (std.mem.eql(u8, algo, "sha256d")) 1024 else 1;
    while (true) {
        const n = link.readLine(&buf) orelse return;
        if (n == 0) continue;
        const line = buf[0..n];
        var method_buf: [32]u8 = undefined;
        var id_buf: [16]u8 = undefined;
        const method = jsonString(line, "method", &method_buf);
        const id = jsonString(line, "id", &id_buf);
        var reply: [700]u8 = undefined;
        if (std.mem.eql(u8, method, "mining.subscribe")) {
            const ua = jsonString(line, "params", &agent);
            if (ua.len > 0) agent_len = @min(ua.len, agent.len);
            if (work.checkedAlgo(algo) == null) {
                const msg = std.fmt.bufPrint(&reply, "{{\"id\":{s},\"result\":null,\"error\":[20,\"algorithm not checked yet\",null]}}\n", .{if (id.len == 0) "1" else id}) catch return;
                _ = link.writeAll(msg) catch return;
                continue;
            }
            if (!chain.ready(port)) {
                const msg = std.fmt.bufPrint(&reply, "{{\"id\":{s},\"result\":null,\"error\":[20,\"pool has no template yet\",null]}}\n", .{if (id.len == 0) "1" else id}) catch return;
                _ = link.writeAll(msg) catch return;
                continue;
            }
            const job = chain.snapshot(port);
            const en1 = job.en1[0..job.en1_len];
            const msg = std.fmt.bufPrint(&reply, "{{\"id\":{s},\"result\":[[[\"mining.notify\",\"ae\"],[\"mining.set_difficulty\",\"ae\"]],\"{s}\",4],\"error\":null}}\n", .{ if (id.len == 0) "1" else id, en1 }) catch return;
            _ = link.writeAll(msg) catch return;
            var diff_msg: [80]u8 = undefined;
            const dline = std.fmt.bufPrint(&diff_msg, "{{\"id\":null,\"method\":\"mining.set_difficulty\",\"params\":[{d}]}}\n", .{diff}) catch return;
            _ = link.writeAll(dline) catch return;
            if (!writeNotify(link, job)) return;
        } else if (std.mem.eql(u8, method, "mining.authorize")) {
            const who = firstQuoted(line);
            worker_len = @min(who.len, worker.len);
            @memcpy(worker[0..worker_len], who[0..worker_len]);
            if (std.mem.indexOf(u8, line, "gpu")) |_| { @memcpy(device[0..3], "gpu"); device_len = 3; }
            if (std.mem.indexOf(u8, line, "asic")) |_| { @memcpy(device[0..4], "asic"); device_len = 4; }
            if (std.mem.indexOf(u8, line, "cpu")) |_| { @memcpy(device[0..3], "cpu"); device_len = 3; }
            var name_buf: [80]u8 = undefined;
            var secret_buf: [32]u8 = undefined;
            const ident = partyAndSecret(line, worker[0..worker_len], &name_buf, &secret_buf);
            pool.lock.lock();
            if (party.enter(ident.name, ident.secret) == .denied) {
                pool.lock.unlock();
                const denied = std.fmt.bufPrint(&reply, "{{\"id\":{s},\"result\":false,\"error\":[24,\"party password\",null]}}\n", .{if (id.len == 0) "2" else id}) catch return;
                _ = link.writeAll(denied) catch return;
                continue;
            }
            authorized = worker_len > 0;
            var existing = false;
            for (pool.workers.items) |*w| if (std.mem.eql(u8, w.name, worker[0..worker_len])) {
                w.device = pool.alloc.dupe(u8, device[0..device_len]) catch w.device;
                w.party = pool.alloc.dupe(u8, ident.name) catch w.party;
                existing = true;
            };
            if (!existing) pool.workers.append(.{
                .name = pool.alloc.dupe(u8, worker[0..worker_len]) catch "",
                .party = pool.alloc.dupe(u8, ident.name) catch "",
                .algo = pool.alloc.dupe(u8, algo) catch "",
                .device = pool.alloc.dupe(u8, device[0..device_len]) catch "",
                .threads = threads,
                .agent = pool.alloc.dupe(u8, agent[0..agent_len]) catch "",
                .shares = 0,
            }) catch {};
            pool.lock.unlock();
            const msg = std.fmt.bufPrint(&reply, "{{\"id\":{s},\"result\":true,\"error\":null}}\n", .{if (id.len == 0) "2" else id}) catch return;
            _ = link.writeAll(msg) catch return;
        } else if (std.mem.eql(u8, method, "mining.submit") and authorized) {
            const verdict = takeSubmit(line, algo, port, worker[0..worker_len], diff);
            if (verdict.ok and verdict.changed) {
                diff = verdict.diff;
                var diff_msg: [96]u8 = undefined;
                if (std.fmt.bufPrint(&diff_msg, "{{\"id\":null,\"method\":\"mining.set_difficulty\",\"params\":[{d}]}}\n", .{diff})) |dline| {
                    _ = link.writeAll(dline) catch {};
                } else |_| {}
            }
            const msg = std.fmt.bufPrint(&reply, "{{\"id\":{s},\"result\":{s},\"error\":{s}}}\n", .{ if (id.len == 0) "3" else id, if (verdict.ok) "true" else "false", verdict.err }) catch return;
            _ = link.writeAll(msg) catch return;
        } else if (method.len == 0 and std.mem.indexOf(u8, line, "\"method\":\"login\"") != null) {
            const msg = std.fmt.bufPrint(&reply, "{{\"id\":1,\"result\":null,\"error\":[20,\"algorithm not checked yet\",null]}}\n", .{}) catch return;
            _ = link.writeAll(msg) catch return;
        }
    }
}

fn writeNotify(link: *Link, job: chain.Job) bool {
    var branches: [1200]u8 = undefined;
    var bn: usize = 0;
    for (job.branch[0..job.branch_n]) |b| {
        if (bn + 70 > branches.len) break;
        if (bn > 0) {
            branches[bn] = ',';
            bn += 1;
        }
        branches[bn] = '"';
        bn += 1;
        const h = work.hexEncode(branches[bn..], &b);
        bn += h.len;
        branches[bn] = '"';
        bn += 1;
    }
    var note: [3200]u8 = undefined;
    const nline = std.fmt.bufPrint(&note, "{{\"id\":null,\"method\":\"mining.notify\",\"params\":[\"{s}\",\"{s}\",\"{s}\",\"{s}\",[{s}],\"{s}\",\"{s}\",\"{s}\",true]}}\n", .{
        job.id[0..job.id_len],
        job.prevhash[0..64],
        job.coinb1[0..job.coinb1_len],
        job.coinb2[0..job.coinb2_len],
        branches[0..bn],
        job.version[0..8],
        job.nbits[0..8],
        job.ntime[0..8],
    }) catch return false;
    link.writeAll(nline) catch return false;
    return true;
}

const Submit = struct { ok: bool, err: []const u8, diff: u32 = 0, changed: bool = false };

fn finish(port: u16, worker: []const u8, kind: []const u8, why: []const u8, ok: bool, err: []const u8, diff: u32, changed: bool) Submit {
    ops.noteShare(port, worker, kind, why);
    return .{ .ok = ok, .err = err, .diff = diff, .changed = changed };
}

fn takeSubmit(line: []const u8, algo: []const u8, port: u16, worker: []const u8, diff: u32) Submit {
    if (work.checkedAlgo(algo) == null) return finish(port, worker, "algo", "algorithm not checked yet", false, "[20,\"algorithm not checked yet\",null]", 0, false);
    var q: [16][]const u8 = undefined;
    const nq = work.quotes(line, &q);
    var at: usize = 0;
    while (at < nq and !std.mem.eql(u8, q[at], "mining.submit")) at += 1;
    if (at + 1 >= nq) return finish(port, worker, "bad", "bad share", false, "[22,\"bad share\",null]", 0, false);
    var rest = q[at + 1 .. nq];
    if (rest.len > 0 and std.mem.eql(u8, rest[0], "params")) rest = rest[1..];
    if (rest.len < 5) return finish(port, worker, "bad", "bad share", false, "[22,\"bad share\",null]", 0, false);
    const job_id = rest[1];
    const en2 = rest[2];
    const ntime = rest[3];
    const nonce = rest[4];
    const job = chain.snapshot(port);
    if (!job.ready) return finish(port, worker, "no-job", "pool has no template yet", false, "[20,\"pool has no template yet\",null]", 0, false);
    if (job.id_len > 0 and !std.mem.eql(u8, job_id, job.id[0..job.id_len])) {
        pool.lock.lock();
        pool.rejected += 1;
        for (pool.workers.items) |w| if (std.mem.eql(u8, w.name, worker)) party.markStale(w.party);
        pool.lock.unlock();
        return finish(port, worker, "stale", "stale job", false, "[21,\"stale job\",null]", 0, false);
    }
    const checked = work.check(pool.alloc, algo, job.version[0..8], job.prevhash[0..64], job.coinb1[0..job.coinb1_len], job.en1[0..job.en1_len], en2, job.coinb2[0..job.coinb2_len], job.branch[0..job.branch_n], ntime, job.nbits[0..8], nonce, diff, true);
    if (checked.verdict == .low) {
        pool.lock.lock();
        pool.rejected += 1;
        pool.lock.unlock();
        return finish(port, worker, "low", "does not meet target", false, "[23,\"does not meet target\",null]", 0, false);
    }
    if (checked.verdict == .bad or checked.verdict == .no_job or checked.verdict == .algo) {
        pool.lock.lock();
        pool.rejected += 1;
        pool.lock.unlock();
        const why = if (checked.verdict == .algo) "algorithm not checked yet" else if (checked.verdict == .no_job) "pool has no template yet" else "bad share";
        const err = if (checked.verdict == .algo) "[20,\"algorithm not checked yet\",null]" else if (checked.verdict == .no_job) "[20,\"pool has no template yet\",null]" else "[22,\"bad share\",null]";
        const kind = if (checked.verdict == .algo) "algo" else if (checked.verdict == .no_job) "no-job" else "bad";
        return finish(port, worker, kind, why, false, err, 0, false);
    }
    const slot = chain.find(port);
    const upstream = if (slot) |s| s.upstream_len > 3 and s.rpc_len < 8 else false;
    if (upstream and !chain.forward(port, job_id, en2, ntime, nonce)) {
        pool.lock.lock();
        pool.rejected += 1;
        pool.lock.unlock();
        return finish(port, worker, "upstream", "upstream refused the share", false, "[23,\"upstream refused the share\",null]", 0, false);
    }
    var coin: [1400]u8 = undefined;
    const coinbase = work.assemble(job.coinb1[0..job.coinb1_len], job.en1[0..job.en1_len], en2, job.coinb2[0..job.coinb2_len], &coin);
    var confirmed = false;
    var aux_pay: u64 = 0;
    var aux_port: u16 = 0;
    var aux_height: u32 = 0;
    if (checked.verdict == .block) {
        if (upstream) {
            confirmed = true;
        } else if (coinbase) |cb| {
            confirmed = chain.acceptBlock(port, checked.header, cb);
            if (confirmed) chain.refresh(port);
            if (confirmed and chain.acceptAux(port, checked.header, cb, job.branch[0..job.branch_n])) {
                aux_pay = job.aux_value;
                if (chain.mergeOf(port)) |child| {
                    chain.refresh(child.port);
                    aux_port = child.port;
                    aux_height = chain.tip(child.port);
                }
            }
        }
    }
    pool.lock.lock();
    pool.accepted += 1;
    if (confirmed) pool.blocks += 1;
    var new_diff = diff;
    var changed = false;
    for (pool.workers.items) |*w| {
        if (!std.mem.eql(u8, w.name, worker)) continue;
        w.shares += 1;
        w.diff = diff;
        w.round += diff;
        w.seen = compat.time.timestamp();
        if (adjustDiff(w, w.seen)) {
            new_diff = w.diff;
            changed = true;
        }
        party.credit(w.party, diff);
        modules.credit(port, worker, diff);
    }
    if (confirmed) closeParty(partyOf(worker), job.subsidy, aux_pay, job.height, port, aux_port, aux_height);
    pool.lock.unlock();
    saveParty();
    writePayouts();
    saveParty();
    if (checked.verdict == .block and confirmed) return finish(port, worker, "block", "node or upstream accepted the block", true, "null", new_diff, changed);
    if (checked.verdict == .block) {
        const note = chain.submitText();
        return finish(port, worker, "block-unconfirmed", if (note.len == 0) "share met the network target but the node did not accept it" else note, true, "null", new_diff, changed);
    }
    return finish(port, worker, "share", "met the job target", true, "null", new_diff, changed);
}

fn listen(port: u16, algo: []const u8) void {
    if (port <= 55535) {
        const tls_port: u16 = port + 10000;
        const tls_thread = std.Thread.spawn(.{}, listenTls, .{ tls_port, algo, port }) catch null;
        if (tls_thread) |t| t.detach();
    }
    const addr = compat.net.Address.parseIp4("0.0.0.0", port) catch return;
    var server = addr.listen(.{ .reuse_address = true }) catch return;
    std.debug.print("Stratum {s} on 0.0.0.0:{d}  tls {d}\n", .{ algo, port, port + 10000 });
    while (true) {
        const conn = server.accept() catch continue;
        const thread = std.Thread.spawn(.{}, serve, .{ conn, algo, port }) catch continue;
        thread.detach();
    }
}

fn listenTls(tls_port: u16, algo: []const u8, port: u16) void {
    const addr = compat.net.Address.parseIp4("0.0.0.0", tls_port) catch return;
    var server = addr.listen(.{ .reuse_address = true }) catch return;
    while (true) {
        const conn = server.accept() catch continue;
        const thread = std.Thread.spawn(.{}, serveTls, .{ conn, algo, port }) catch continue;
        thread.detach();
    }
}

fn adjustDiff(w: *Pool.Worker, now: i64) bool {
    const share: u64 = if (w.diff == 0) 1 else w.diff;
    w.window_diff += share;
    w.vardiff_n += 1;
    if (w.window_at == 0) w.window_at = now;
    const elapsed = now - w.window_at;
    if (elapsed > 0) w.hashrate = work.hashrate(w.window_diff, elapsed);
    if (elapsed < 8 or w.vardiff_n < 2) return false;
    const want128: u128 = @as(u128, w.hashrate) * 15;
    var want: u64 = @intCast(@min(want128 >> 32, @as(u128, 1 << 20)));
    const floor: u32 = if (std.mem.eql(u8, w.algo, "sha256d")) 16 else 1;
    if (want < floor) want = floor;
    var next: u32 = if (w.diff == 0) floor else w.diff;
    const want32: u32 = @intCast(@min(want, @as(u64, 1 << 20)));
    if (want32 > next) {
        const doubled = if (next > (1 << 18)) next else next * 2;
        next = @min(doubled, want32);
    } else if (want32 < next) {
        next = @max(@max(next / 2, floor), want32);
    }
    if (next < floor) next = floor;
    w.window_diff = 0;
    w.window_at = now;
    w.vardiff_n = 0;
    if (next == w.diff) return false;
    w.diff = next;
    return true;
}

const Due = struct {
    name: [80]u8 = @splat(0),
    name_len: usize = 0,
    amount: u64 = 0,
    height: u32 = 0,
    port: u16 = 0,
};
var due: [128]Due = undefined;
var due_n: usize = 0;

fn hold(name: []const u8, amount: u64, height: u32, port: u16) void {
    if (amount == 0 or height == 0 or port == 0 or due_n >= due.len) return;
    const n = @min(name.len, due[due_n].name.len);
    @memcpy(due[due_n].name[0..n], name[0..n]);
    due[due_n].name_len = n;
    due[due_n].amount = amount;
    due[due_n].height = height;
    due[due_n].port = port;
    due_n += 1;
    for (pool.workers.items) |*w| {
        if (std.mem.eql(u8, w.name, name)) w.immature += amount;
    }
    saveDue();
}

fn saveDue() void {
    var buf = std.array_list.Managed(u8).init(pool.alloc);
    defer buf.deinit();
    buf.appendSlice("# worker  sats  height  port\n") catch return;
    for (due[0..due_n]) |d| {
        buf.print("{s}\t{d}\t{d}\t{d}\n", .{ d.name[0..d.name_len], d.amount, d.height, d.port }) catch return;
    }
    var file = compat.fs.cwd().createFile("due.cfg.tmp", .{}) catch return;
    file.writeAll(buf.items) catch {
        file.close();
        return;
    };
    file.close();
    compat.fs.cwd().rename("due.cfg.tmp", "due.cfg") catch {};
}

fn loadDue() void {
    const raw = compat.fs.cwd().readFileAlloc(pool.alloc, "due.cfg", 1 << 16) catch return;
    defer pool.alloc.free(raw);
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (line.len < 3 or line[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, line, '\t');
        const name = parts.next() orelse continue;
        const amount = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        const height = std.fmt.parseInt(u32, parts.next() orelse "0", 10) catch 0;
        const port = std.fmt.parseInt(u16, parts.next() orelse "0", 10) catch 0;
        if (amount == 0 or height == 0 or port == 0 or due_n >= due.len) continue;
        const n = @min(name.len, due[due_n].name.len);
        @memcpy(due[due_n].name[0..n], name[0..n]);
        due[due_n].name_len = n;
        due[due_n].amount = amount;
        due[due_n].height = height;
        due[due_n].port = port;
        due_n += 1;
        var found = false;
        for (pool.workers.items) |*w| {
            if (!std.mem.eql(u8, w.name, name)) continue;
            w.immature += amount;
            found = true;
        }
        if (!found) {
            pool.workers.append(.{
                .name = pool.alloc.dupe(u8, name) catch "",
                .party = pool.alloc.dupe(u8, partyOf(name)) catch "",
                .algo = pool.alloc.dupe(u8, "sha256d") catch "",
                .device = pool.alloc.dupe(u8, "saved") catch "",
                .threads = 0,
                .agent = pool.alloc.dupe(u8, "disk") catch "",
            }) catch {};
            if (pool.workers.items.len > 0) pool.workers.items[pool.workers.items.len - 1].immature = amount;
        }
    }
    std.debug.print("loaded {d} immature credits from due.cfg\n", .{due_n});
}

fn releaseMature() void {
    pool.lock.lock();
    defer pool.lock.unlock();
    var i: usize = 0;
    while (i < due_n) {
        if (!work.matured(chain.tip(due[i].port), due[i].height)) {
            i += 1;
            continue;
        }
        const name = due[i].name[0..due[i].name_len];
        const amt = due[i].amount;
        for (pool.workers.items) |*w| {
            if (!std.mem.eql(u8, w.name, name)) continue;
            if (w.immature >= amt) w.immature -= amt else w.immature = 0;
            w.balance += amt;
        }
        due_n -= 1;
        due[i] = due[due_n];
    }
    saveDue();
}

fn closeParty(name: []const u8, reward: u64, aux_reward: u64, height: u32, port: u16, aux_port: u16, aux_height: u32) void {
    var n: usize = 0;
    for (pool.workers.items) |w| {
        if (std.mem.eql(u8, w.party, name)) n += 1;
    }
    if (n == 0 or (reward == 0 and aux_reward == 0)) return;
    var shares_buf: [64]u64 = undefined;
    var idx: [64]usize = undefined;
    var i: usize = 0;
    for (pool.workers.items, 0..) |w, wi| {
        if (!std.mem.eql(u8, w.party, name) or i >= shares_buf.len) continue;
        shares_buf[i] = w.round;
        idx[i] = wi;
        i += 1;
    }
    var cuts: [64]u64 = undefined;
    var aux_cuts: [64]u64 = undefined;
    const given = if (reward > 0) party.split(reward, name, shares_buf[0..i], cuts[0..i], height) else 0;
    const aux_given = if (aux_reward > 0) party.split(aux_reward, name, shares_buf[0..i], aux_cuts[0..i], height) else 0;
    var note = std.array_list.Managed(u8).init(pool.alloc);
    defer note.deinit();
    note.print("block  height {d}  party {s}  subsidy {d}  paid {d}  merge {d}\n", .{ height, name, reward, given, aux_given }) catch {};
    for (0..i) |k| {
        const cut = if (reward > 0) cuts[k] else 0;
        const extra = if (aux_reward > 0) aux_cuts[k] else 0;
        pool.workers.items[idx[k]].round = 0;
        hold(pool.workers.items[idx[k]].name, cut, height, port);
        hold(pool.workers.items[idx[k]].name, extra, aux_height, aux_port);
        note.print("  {s}  {d}  immature until 100\n", .{ pool.workers.items[idx[k]].name, cut + extra }) catch {};
    }
    const previous = compat.fs.cwd().readFileAlloc(pool.alloc, "rounds.log", 1 << 20) catch null;
    if (previous) |prev| {
        note.insertSlice(0, prev) catch {};
        pool.alloc.free(prev);
    }
    var log = compat.fs.cwd().createFile("rounds.log", .{}) catch return;
    log.writeAll(note.items) catch {};
    log.close();
}

fn payAt() u64 {
    const raw = compat.getEnv(pool.alloc, "THIMBLE_PAY_SATS") catch return 100_000;
    defer pool.alloc.free(raw);
    return std.fmt.parseInt(u64, raw, 10) catch 100_000;
}

fn payAddress(worker: []const u8) ?[]const u8 {
    const cut = if (std.mem.indexOfScalar(u8, worker, '.')) |d| worker[0..d] else worker;
    if (cut.len < 14 or cut.len > 90) return null;
    var script: [80]u8 = undefined;
    if (work.outputScript(cut, &script) == null) return null;
    return cut;
}

fn writePayouts() void {
    releaseMature();
    var buf = std.array_list.Managed(u8).init(pool.alloc);
    defer buf.deinit();
    buf.appendSlice("# screen  balance  min 1000 before a send\n") catch return;
    for (pool.workers.items) |w| {
        buf.print("{s}\t{d}\n", .{ w.name, w.balance }) catch return;
    }
    var file = compat.fs.cwd().createFile("payouts.cfg.tmp", .{}) catch return;
    file.writeAll(buf.items) catch {
        file.close();
        return;
    };
    file.close();
    compat.fs.cwd().rename("payouts.cfg.tmp", "payouts.cfg") catch {};
    const threshold = payAt();
    var i: usize = 0;
    while (i < pool.workers.items.len) : (i += 1) {
        const addr = payAddress(pool.workers.items[i].name) orelse continue;
        var addr_buf: [90]u8 = undefined;
        if (addr.len > addr_buf.len) continue;
        @memcpy(addr_buf[0..addr.len], addr);
        pool.lock.lock();
        if (i >= pool.workers.items.len or pool.workers.items[i].balance < threshold) {
            pool.lock.unlock();
            continue;
        }
        const amt = pool.workers.items[i].balance;
        const port = portOf(pool.workers.items[i].algo);
        pool.workers.items[i].balance = 0;
        pool.lock.unlock();
        const resp = chain.sendTo(port, addr_buf[0..addr.len], amt);
        var txbuf: [80]u8 = @splat(0);
        var txlen: usize = 7;
        @memcpy(txbuf[0..7], "no node");
        var ok = false;
        if (resp) |body| {
            defer pool.alloc.free(body);
            if (std.mem.indexOf(u8, body, "\"result\":\"")) |at| {
                const from = at + 10;
                const end = std.mem.indexOfScalarPos(u8, body, from, '"') orelse from;
                if (end > from and std.mem.indexOf(u8, body, "\"error\":null") != null) {
                    txlen = @min(txbuf.len, end - from);
                    @memcpy(txbuf[0..txlen], body[from .. from + txlen]);
                    ok = true;
                }
            }
            if (!ok) {
                txlen = 12;
                @memcpy(txbuf[0..12], "node refused");
            }
        }
        var row: [240]u8 = undefined;
        const line = std.fmt.bufPrint(&row, "{d}\t{s}\t{d}\t{s}\n", .{ compat.time.timestamp(), addr_buf[0..addr.len], amt, txbuf[0..txlen] }) catch continue;
        const previous = compat.fs.cwd().readFileAlloc(pool.alloc, "payouts.log", 1 << 20) catch null;
        var log = compat.fs.cwd().createFile("payouts.log", .{}) catch continue;
        if (previous) |prev| {
            log.writeAll(prev) catch {};
            pool.alloc.free(prev);
        }
        log.writeAll(line) catch {};
        log.close();
        if (!ok) {
            pool.lock.lock();
            if (i < pool.workers.items.len) pool.workers.items[i].balance += amt;
            pool.lock.unlock();
        }
    }
}

fn portOf(algo: []const u8) u16 {
    for (modules.mods[0..modules.count]) |m| if (std.mem.eql(u8, m.algo[0..m.algo_len], algo)) return m.port;
    for (algos, ports) |a, p| if (std.mem.eql(u8, a, algo)) return p;
    return 0;
}

pub fn start() !void {
    chain.start();
    modules.load();
    chain.attach();
    party.load(pool.alloc);
    loadParty();
    var enabled: [ports.len]bool = @splat(true);
    if (compat.fs.cwd().readFileAlloc(pool.alloc, "pools.cfg", 1 << 16)) |raw| {
        for (&enabled) |*on| on.* = false;
        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            var parts = std.mem.splitScalar(u8, line, '\t');
            _ = parts.next();
            _ = parts.next();
            const port = std.fmt.parseInt(u16, parts.next() orelse "0", 10) catch 0;
            const on = std.mem.eql(u8, parts.next() orelse "0", "1");
            if (!on) continue;
            for (ports, 0..) |p, i| {
                if (p == port) enabled[i] = true;
            }
        }
        pool.alloc.free(raw);
        var any = false;
        for (enabled) |on| {
            if (on) any = true;
        }
        if (!any) {
            for (&enabled) |*flag| flag.* = false;
        }
    } else |_| {
        for (&enabled) |*flag| flag.* = false;
        enabled[0] = true;
    }
    for (algos, ports, enabled) |algo, port, on| {
        if (!on) continue;
        const thread = try std.Thread.spawn(.{}, waitListen, .{ port, algo });
        thread.detach();
    }
}

fn waitListen(port: u16, algo: []const u8) void {
    while (!chain.ready(port)) compat.time.sleep(2 * std.time.ns_per_s);
    listen(port, algo);
}
