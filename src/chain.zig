const compat = @import("compat.zig");
const modules = @import("modules.zig");
const std = @import("std");
const work = @import("work.zig");

pub const State = enum { no_node, syncing, headers, pruned, ready, upstream };

pub const Job = struct {
    id: [32]u8 = @splat(0),
    id_len: usize = 0,
    prevhash: [64]u8 = @splat(0),
    version: [8]u8 = @splat(0),
    nbits: [8]u8 = @splat(0),
    ntime: [8]u8 = @splat(0),
    coinb1: [1600]u8 = @splat(0),
    coinb1_len: usize = 0,
    coinb2: [1600]u8 = @splat(0),
    coinb2_len: usize = 0,
    branch: [16][32]u8 = @splat(@splat(0)),
    branch_n: usize = 0,
    en1: [16]u8 = .{ 'a', 'e', '0', '1', '0', '0', '0', '0', 0, 0, 0, 0, 0, 0, 0, 0 },
    en1_len: usize = 8,
    height: u32 = 0,
    subsidy: u64 = 0,
    fees: u64 = 0,
    ready: bool = false,
    aux_hex: [64]u8 = @splat(0),
    aux_len: usize = 0,
    aux_value: u64 = 0,
};

pub const Source = struct {
    used: bool = false,
    port: u16 = 0,
    algo: [16]u8 = @splat(0),
    algo_len: usize = 0,
    name: [32]u8 = @splat(0),
    name_len: usize = 0,
    merge: [32]u8 = @splat(0),
    merge_len: usize = 0,
    wallet: [80]u8 = @splat(0),
    wallet_len: usize = 0,
    rpc: [180]u8 = @splat(0),
    rpc_len: usize = 0,
    upstream: [96]u8 = @splat(0),
    upstream_len: usize = 0,
    lock: compat.Mutex = .{},
    job: Job = .{},
    state: State = .no_node,
    peers: u32 = 0,
    height: u32 = 0,
    ibd: bool = false,
    pruned: bool = false,
    blocks_found: u32 = 0,
    chain_tip: u32 = 0,
    err: [160]u8 = @splat(0),
    err_len: usize = 0,
};

pub var slots: [8]Source = .{ .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{} };

var build_stage: [32]u8 = @splat(0);
var build_stage_len: usize = 0;
var build_detail: [180]u8 = @splat(0);
var build_detail_len: usize = 0;

fn note(s: *Source, text: []const u8) void {
    s.err_len = put(&s.err, text);
}

fn stateName(st: State) []const u8 {
    return switch (st) {
        .no_node => "no node",
        .syncing => "syncing",
        .headers => "headers",
        .pruned => "pruned",
        .ready => "ready",
        .upstream => "upstream",
    };
}

pub fn setStage(stage: []const u8, detail: []const u8) void {
    build_stage_len = put(&build_stage, stage);
    build_detail_len = put(&build_detail, detail);
}

pub fn stageLine(buf: []u8) []const u8 {
    if (build_stage_len == 0) return "no codebase step yet";
    const n = std.fmt.bufPrint(buf, "{s}: {s}", .{ build_stage[0..build_stage_len], build_detail[0..build_detail_len] }) catch return build_stage[0..build_stage_len];
    return n;
}

pub fn progress() usize {
    const s = build_stage[0..build_stage_len];
    if (std.mem.eql(u8, s, "fetching")) return 10;
    if (std.mem.eql(u8, s, "checking")) return 20;
    if (std.mem.eql(u8, s, "downloading")) return 30;
    if (std.mem.eql(u8, s, "cloned")) return 40;
    if (std.mem.eql(u8, s, "compiling")) return 60;
    if (std.mem.eql(u8, s, "compiled")) return 75;
    if (std.mem.eql(u8, s, "connecting")) return 85;
    if (std.mem.eql(u8, s, "syncing")) return 92;
    if (std.mem.eql(u8, s, "ready")) return 100;
    return 0;
}

pub fn statusLine(buf: []u8) []const u8 {
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer out.deinit();
    var any = false;
    for (&slots) |*s| {
        if (!s.used) continue;
        any = true;
        s.lock.lock();
        const open = s.job.ready;
        const sub = s.job.subsidy;
        const peers = s.peers;
        const err = s.err[0..s.err_len];
        out.print("{s} {s} port {d} height {d} peers {d} {s} subsidy {d} {s}\n", .{
            if (s.name_len > 0) s.name[0..s.name_len] else s.algo[0..s.algo_len],
            stateName(s.state),
            s.port,
            s.height,
            peers,
            if (open) "OPEN" else "closed until a template",
            sub,
            err,
        }) catch {};
        s.lock.unlock();
    }
    if (!any) out.appendSlice("no chain configured\n") catch {};
    const n = @min(out.items.len, buf.len);
    @memcpy(buf[0..n], out.items[0..n]);
    return buf[0..n];
}

pub fn forPort(port: u16) *Source {
    for (&slots) |*s| {
        if (s.used and s.port == port) return s;
    }
    for (&slots) |*s| {
        if (!s.used) {
            s.* = .{};
            s.used = true;
            s.port = port;
            return s;
        }
    }
    return &slots[0];
}

pub fn find(port: u16) ?*Source {
    for (&slots) |*s| if (s.used and s.port == port) return s;
    return null;
}

pub fn ready(port: u16) bool {
    const s = find(port) orelse return false;
    s.lock.lock();
    defer s.lock.unlock();
    return s.job.ready;
}

pub fn armed(port: u16) bool {
    const s = find(port) orelse return false;
    if (s.rpc_len > 8 or s.upstream_len > 3) return true;
    return ready(port);
}

fn put(dst: []u8, src: []const u8) usize {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

pub fn setFeed(port: u16, algo: []const u8, text: []const u8) void {
    const s = forPort(port);
    s.algo_len = put(&s.algo, algo);
    if (std.mem.startsWith(u8, text, "http://")) {
        s.rpc_len = put(&s.rpc, text);
        s.upstream_len = 0;
    } else if (text.len > 0 and std.mem.indexOfScalar(u8, text, ':') != null and !std.mem.startsWith(u8, text, "https://")) {
        s.upstream_len = put(&s.upstream, text);
        s.rpc_len = 0;
    }
    s.lock.lock();
    s.job.ready = false;
    s.state = .no_node;
    note(s, "feed set, waiting for a template");
    s.lock.unlock();
}

pub fn setWallet(port: u16, wallet: []const u8) void {
    const s = forPort(port);
    s.wallet_len = put(&s.wallet, wallet);
}

pub fn setMerge(port: u16, name: []const u8) void {
    const s = forPort(port);
    s.merge_len = put(&s.merge, name);
}

fn copyEnv(name: []const u8, dst: []u8) usize {
    const v = compat.getEnv(std.heap.page_allocator, name) catch return 0;
    defer std.heap.page_allocator.free(v);
    return put(dst, v);
}

pub fn attach() void {
    for (modules.mods[0..modules.count]) |m| {
        if (!m.on) continue;
        const s = forPort(m.port);
        s.algo_len = put(&s.algo, m.algo[0..m.algo_len]);
        s.name_len = put(&s.name, m.name[0..m.name_len]);
        s.merge_len = put(&s.merge, m.merge[0..m.merge_len]);
        if (m.wallet_len > 0) s.wallet_len = put(&s.wallet, m.wallet[0..m.wallet_len]);
        const src = m.source[0..m.source_len];
        if (std.mem.startsWith(u8, src, "http://") or (src.len > 0 and std.mem.indexOfScalar(u8, src, ':') != null and !std.mem.startsWith(u8, src, "https://"))) {
            setFeed(m.port, m.algo[0..m.algo_len], src);
            s.wallet_len = put(&s.wallet, m.wallet[0..m.wallet_len]);
            s.merge_len = put(&s.merge, m.merge[0..m.merge_len]);
        }
    }
}

var booted = false;

pub fn applyEnv() void {
    var rpc: [160]u8 = undefined;
    const rn = copyEnv("THIMBLE_RPC", &rpc);
    if (rn > 8) setFeed(3333, "sha256d", rpc[0..rn]);
    var up: [96]u8 = undefined;
    const un = copyEnv("THIMBLE_UPSTREAM", &up);
    if (un > 3) setFeed(3333, "sha256d", up[0..un]);
    var wal: [80]u8 = undefined;
    const wn = copyEnv("THIMBLE_WALLET", &wal);
    if (wn > 0) setWallet(3333, wal[0..wn]);
}

pub fn start() void {
    if (booted) return;
    booted = true;
    applyEnv();
    const watch_thread = std.Thread.spawn(.{}, watch, .{}) catch return;
    watch_thread.detach();
    for (0..slots.len) |i| {
        const t = std.Thread.spawn(.{}, upstreamLoop, .{i}) catch continue;
        t.detach();
    }
}

fn hostPort(text: []const u8, out_host: []u8, out_port: *u16) ?[]const u8 {
    var s = text;
    if (std.mem.indexOf(u8, s, "://")) |i| s = s[i + 3 ..];
    if (std.mem.indexOfScalar(u8, s, '@')) |at| s = s[at + 1 ..];
    const colon = std.mem.lastIndexOfScalar(u8, s, ':') orelse return null;
    const n = @min(s[0..colon].len, out_host.len);
    @memcpy(out_host[0..n], s[0..colon]);
    out_port.* = std.fmt.parseInt(u16, s[colon + 1 ..], 10) catch 8332;
    return out_host[0..n];
}

fn connectHost(alloc: std.mem.Allocator, host: []const u8, port: u16) ?compat.net.Stream {
    _ = alloc;
    return compat.net.connectHost(host, port) catch null;
}

fn httpPost(alloc: std.mem.Allocator, url: []const u8, body: []const u8) ?[]u8 {
    const at = std.mem.indexOfScalar(u8, url, '@') orelse return null;
    const scheme = std.mem.indexOf(u8, url, "://") orelse return null;
    const auth = url[scheme + 3 .. at];
    var host_buf: [80]u8 = undefined;
    var port: u16 = 8332;
    const host = hostPort(url, &host_buf, &port) orelse return null;
    const stream = connectHost(alloc, host, port) orelse return null;
    defer stream.close();
    var auth_buf: [180]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&auth_buf, auth);
    var head: [400]u8 = undefined;
    const h = std.fmt.bufPrint(&head, "POST / HTTP/1.1\r\nHost: {s}:{d}\r\nAuthorization: Basic {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ host, port, b64, body.len }) catch return null;
    stream.writeAll(h) catch return null;
    stream.writeAll(body) catch return null;
    return stream.reader().readAllAlloc(alloc, 8 << 20) catch null;
}

fn jsonU64(text: []const u8, key: []const u8) ?u64 {
    var pat: [40]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "\"{s}\":", .{key}) catch return null;
    const at = std.mem.indexOf(u8, text, p) orelse return null;
    var i = at + p.len;
    while (i < text.len and (text[i] == ' ' or text[i] == '"')) i += 1;
    var n: u64 = 0;
    var any = false;
    while (i < text.len and text[i] >= '0' and text[i] <= '9') : (i += 1) {
        any = true;
        n = n * 10 + (text[i] - '0');
    }
    return if (any) n else null;
}

fn jsonBool(text: []const u8, key: []const u8) bool {
    var pat: [40]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "\"{s}\":true", .{key}) catch return false;
    return std.mem.indexOf(u8, text, p) != null;
}

fn copyField(text: []const u8, key: []const u8, dst: []u8) usize {
    var pat: [48]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "\"{s}\":\"", .{key}) catch return 0;
    const at = std.mem.indexOf(u8, text, p) orelse return 0;
    var i = at + p.len;
    var n: usize = 0;
    while (i < text.len and text[i] != '"' and n < dst.len) : (i += 1) {
        dst[n] = text[i];
        n += 1;
    }
    return n;
}

fn bodyOf(text: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, text, "\r\n\r\n") orelse return text;
    return text[at + 4 ..];
}

fn pollRpc(s: *Source, alloc: std.mem.Allocator) void {
    const info_raw = httpPost(alloc, s.rpc[0..s.rpc_len], "{\"jsonrpc\":\"1.0\",\"id\":\"h\",\"method\":\"getblockchaininfo\",\"params\":[]}") orelse {
        s.lock.lock();
        s.state = .no_node;
        s.job.ready = false;
        note(s, "rpc down");
        s.lock.unlock();
        return;
    };
    defer alloc.free(info_raw);
    const info = bodyOf(info_raw);
    const height: u32 = @intCast(jsonU64(info, "blocks") orelse 0);
    const header_n: u32 = @intCast(jsonU64(info, "headers") orelse height);
    const ibd = jsonBool(info, "initialblockdownload");
    const pruned = jsonBool(info, "pruned");
    const peers_raw = httpPost(alloc, s.rpc[0..s.rpc_len], "{\"jsonrpc\":\"1.0\",\"id\":\"p\",\"method\":\"getconnectioncount\",\"params\":[]}");
    const peers: u32 = if (peers_raw) |p| blk: {
        defer alloc.free(p);
        break :blk @intCast(jsonU64(bodyOf(p), "result") orelse 0);
    } else 0;
    s.lock.lock();
    s.height = height;
    s.chain_tip = height;
    s.peers = peers;
    s.ibd = ibd;
    s.pruned = pruned;
    if (ibd) {
        s.state = .syncing;
        s.job.ready = false;
        note(s, "node is downloading the chain. port stays closed");
    }
    s.lock.unlock();
    if (modules.byPort(s.port)) |m| m.height = height;
    if (ibd) {
        s.lock.lock();
        s.state = .syncing;
        note(s, "node is downloading the chain");
        s.lock.unlock();
        var detail: [80]u8 = undefined;
        const d = std.fmt.bufPrint(&detail, "port {d} height {d}. waiting for a template", .{ s.port, height }) catch return;
        setStage("syncing", d);
    } else if (header_n > height) {
        s.lock.lock();
        s.state = .headers;
        s.lock.unlock();
    }
    fillTemplate(s, alloc);
}

fn fillTemplate(s: *Source, alloc: std.mem.Allocator) void {
    const bodies = [_][]const u8{
        "{\"jsonrpc\":\"1.0\",\"id\":\"t\",\"method\":\"getblocktemplate\",\"params\":[{\"rules\":[\"segwit\",\"mweb\"]}]}",
        "{\"jsonrpc\":\"1.0\",\"id\":\"t\",\"method\":\"getblocktemplate\",\"params\":[{\"rules\":[\"segwit\"]}]}",
        "{\"jsonrpc\":\"1.0\",\"id\":\"t\",\"method\":\"getblocktemplate\",\"params\":[{}]}",
    };
    const doge = std.mem.eql(u8, s.name[0..s.name_len], "Dogecoin");
    const scrypt = std.mem.eql(u8, s.algo[0..s.algo_len], "scrypt");
    const order = if (doge) [_]u8{ 1, 2, 0 } else if (scrypt) [_]u8{ 0, 1, 2 } else [_]u8{ 1, 2, 0 };
    var chosen: ?[]u8 = null;
    for (order) |idx| {
        const raw_http = httpPost(alloc, s.rpc[0..s.rpc_len], bodies[idx]) orelse continue;
        const raw = bodyOf(raw_http);
        var prev_try: [64]u8 = undefined;
        if (std.mem.indexOf(u8, raw, "\"result\":null") != null or copyField(raw, "previousblockhash", &prev_try) != 64) {
            alloc.free(raw_http);
            continue;
        }
        chosen = raw_http;
        break;
    }
    const raw_http = chosen orelse {
        s.lock.lock();
        note(s, "no template yet");
        s.job.ready = false;
        s.lock.unlock();
        return;
    };
    defer alloc.free(raw_http);
    const raw = bodyOf(raw_http);
    const height: u32 = @intCast(jsonU64(raw, "height") orelse 0);
    var prev_disp: [64]u8 = undefined;
    if (copyField(raw, "previousblockhash", &prev_disp) != 64) return;
    var bits: [16]u8 = undefined;
    const bits_n = copyField(raw, "bits", &bits);
    if (bits_n < 8) return;
    const value = jsonU64(raw, "coinbasevalue") orelse 0;
    var witness: [120]u8 = undefined;
    const witness_n = copyField(raw, "default_witness_commitment", &witness);
    var script_try: [80]u8 = undefined;
    if (work.outputScript(s.wallet[0..s.wallet_len], &script_try) == null) {
        s.lock.lock();
        s.job.ready = false;
        s.height = if (height > 0) height else s.height;
        note(s, "wallet must be base58 or bc1. port stays closed");
        s.lock.unlock();
        return;
    }
    var aux: ?[32]u8 = null;
    var aux_hex: [64]u8 = @splat(0);
    var aux_len: usize = 0;
    var aux_value: u64 = 0;
    if (s.merge_len > 1 and !std.mem.eql(u8, s.merge[0..s.merge_len], "none")) {
        if (pullAux(s, alloc, &aux_hex, &aux_len, &aux_value)) |hash| aux = hash;
    }
    const built = work.buildCoinbase(height, if (value == 0) work.subsidy(s.algo[0..s.algo_len], height) else value, s.wallet[0..s.wallet_len], aux, witness[0..witness_n]) orelse {
        s.lock.lock();
        s.job.ready = false;
        note(s, "wallet is not base58 or bc1");
        s.lock.unlock();
        return;
    };
    const txids = alloc.alloc([32]u8, 8000) catch return;
    defer alloc.free(txids);
    var tn: usize = 0;
    var fees: u64 = 0;
    var scan: usize = 0;
    while (scan < raw.len and tn < txids.len) {
        const at = std.mem.findPos(u8, raw, scan, "\"fee\":") orelse break;
        if (jsonU64(raw[at..@min(raw.len, at + 40)], "fee")) |f| fees += f;
        scan = at + 6;
    }
    compat.fs.cwd().makePath("jobs") catch return;
    var path: [40]u8 = undefined;
    const path_s = std.fmt.bufPrint(&path, "jobs/{d}.txs", .{s.port}) catch return;
    var file = compat.fs.cwd().createFile(path_s, .{}) catch return;
    defer file.close();
    const scratch = alloc.alloc(u8, 256 * 1024) catch return;
    defer alloc.free(scratch);
    scan = 0;
    var stored: u32 = 0;
    while (scan < raw.len) {
        const at = std.mem.findPos(u8, raw, scan, "\"data\":\"") orelse break;
        var i = at + 8;
        const hex_at = i;
        while (i < raw.len and raw[i] != '"') i += 1;
        const hex = raw[hex_at..i];
        scan = i + 1;
        if (hex.len < 20 or hex.len / 2 > scratch.len) continue;
        const got = work.hexDecode(scratch, hex) orelse continue;
        var lenb: [4]u8 = undefined;
        std.mem.writeInt(u32, &lenb, @intCast(got.len), .little);
        file.writeAll(&lenb) catch return;
        file.writeAll(got) catch return;
        stored += 1;
    }
    scan = 0;
    while (scan < raw.len and tn < txids.len) {
        const at = std.mem.findPos(u8, raw, scan, "\"txid\":\"") orelse break;
        var disp: [32]u8 = undefined;
        const hex = raw[at + 8 .. @min(raw.len, at + 8 + 64)];
        scan = at + 8;
        if (hex.len < 64) break;
        const got = work.hexDecode(&disp, hex[0..64]) orelse continue;
        var internal: [32]u8 = undefined;
        for (0..32) |k| internal[k] = got[31 - k];
        txids[tn] = internal;
        tn += 1;
        scan = at + 72;
    }
    var branch: [16][32]u8 = undefined;
    const dummy: [32]u8 = @splat(0);
    const bn = work.coinbaseBranch(dummy, txids[0..tn], &branch);
    const pay = if (value > fees) value - fees else work.subsidy(s.algo[0..s.algo_len], height);
    const ver: u32 = @intCast(jsonU64(raw, "version") orelse 0x20000000);
    const cur: u32 = @intCast(jsonU64(raw, "curtime") orelse @as(u64, @intCast(@max(compat.time.timestamp(), 0))));
    s.lock.lock();
    defer s.lock.unlock();
    var idbuf: [16]u8 = undefined;
    const id = std.fmt.bufPrint(&idbuf, "{d}", .{height}) catch return;
    s.job.id_len = put(&s.job.id, id);
    work.reverseGroups(&s.job.prevhash, &prev_disp);
    _ = std.fmt.bufPrint(&s.job.version, "{x:0>8}", .{ver}) catch return;
    s.job.nbits = .{ '1', 'd', '0', '0', 'f', 'f', 'f', 'f' };
    @memcpy(s.job.nbits[0..@min(bits_n, 8)], bits[0..@min(bits_n, 8)]);
    _ = std.fmt.bufPrint(&s.job.ntime, "{x:0>8}", .{cur}) catch return;
    s.job.coinb1_len = put(&s.job.coinb1, built.coinb1[0..built.coinb1_len]);
    s.job.coinb2_len = put(&s.job.coinb2, built.coinb2[0..built.coinb2_len]);
    s.job.branch_n = @min(bn, s.job.branch.len);
    @memcpy(s.job.branch[0..s.job.branch_n], branch[0..s.job.branch_n]);
    s.job.height = height;
    s.job.subsidy = pay;
    s.job.fees = fees;
    s.job.ready = stored > 0 or tn == 0;
    s.job.aux_len = put(&s.job.aux_hex, aux_hex[0..aux_len]);
    s.job.aux_value = aux_value;
    s.height = height;
    s.state = if (s.pruned) .pruned else .ready;
    note(s, if (s.job.ready) "template live. port is open" else "template had no transactions");
    if (s.job.ready) setStage("ready", "template is live. miners can connect");
}

fn pullAux(parent: *Source, alloc: std.mem.Allocator, hex_out: []u8, hex_len: *usize, value_out: *u64) ?[32]u8 {
    const want = parent.merge[0..parent.merge_len];
    for (&slots) |*s| {
        if (!s.used or s.rpc_len < 8) continue;
        if (!std.mem.eql(u8, s.name[0..s.name_len], want)) continue;
        const who = if (s.wallet_len > 20) s.wallet[0..s.wallet_len] else parent.wallet[0..parent.wallet_len];
        var body: [220]u8 = undefined;
        const req = std.fmt.bufPrint(&body, "{{\"jsonrpc\":\"1.0\",\"id\":\"a\",\"method\":\"createauxblock\",\"params\":[\"{s}\"]}}", .{who}) catch return null;
        const raw = httpPost(alloc, s.rpc[0..s.rpc_len], req) orelse {
            remember("createauxblock did not answer");
            return null;
        };
        defer alloc.free(raw);
        var disp: [64]u8 = undefined;
        const n = copyField(bodyOf(raw), "hash", &disp);
        if (n != 64) {
            const replied = bodyOf(raw);
            remember(replied[0..@min(replied.len, submit_note.len)]);
            return null;
        }
        value_out.* = jsonU64(bodyOf(raw), "coinbasevalue") orelse 0;
        hex_len.* = put(hex_out, disp[0..n]);
        var rawb: [32]u8 = undefined;
        _ = work.hexDecode(&rawb, disp[0..64]) orelse return null;
        return rawb;
    }
    return null;
}

fn watch() void {
    const alloc = std.heap.page_allocator;
    while (true) {
        for (&slots) |*s| {
            if (!s.used or s.rpc_len < 8) continue;
            pollRpc(s, alloc);
        }
        compat.time.sleep(5 * std.time.ns_per_s);
    }
}

fn takeEn1(line: []const u8, s: *Source) void {
    var q: [16][]const u8 = undefined;
    const n = work.quotes(line, &q);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const item = q[i];
        if (item.len < 4 or item.len > 8 or item.len % 2 != 0) continue;
        var hex = true;
        for (item) |c| {
            if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'))) hex = false;
        }
        if (!hex) continue;
        s.lock.lock();
        s.job.en1_len = put(&s.job.en1, item);
        s.lock.unlock();
    }
}

fn takeNotify(line: []const u8, s: *Source) void {
    var q: [24][]const u8 = undefined;
    const n = work.quotes(line, &q);
    var from: usize = 0;
    while (from < n and !std.mem.eql(u8, q[from], "mining.notify")) from += 1;
    if (from + 4 >= n) return;
    const rest = q[from + 1 ..];
    if (rest.len < 7) return;
    const version = rest[rest.len - 3];
    const nbits = rest[rest.len - 2];
    const ntime = rest[rest.len - 1];
    if (rest[1].len < 64 or nbits.len < 8) return;
    s.lock.lock();
    defer s.lock.unlock();
    s.job.id_len = put(&s.job.id, rest[0]);
    @memcpy(s.job.prevhash[0..64], rest[1][0..64]);
    s.job.coinb1_len = put(&s.job.coinb1, rest[2]);
    s.job.coinb2_len = put(&s.job.coinb2, rest[3]);
    s.job.branch_n = 0;
    var b: usize = 4;
    while (b + 3 < rest.len and s.job.branch_n < s.job.branch.len) : (b += 1) {
        var rawb: [32]u8 = undefined;
        const got = work.hexDecode(&rawb, rest[b]) orelse break;
        if (got.len != 32) break;
        s.job.branch[s.job.branch_n] = rawb;
        s.job.branch_n += 1;
    }
    @memcpy(s.job.version[0..@min(8, version.len)], version[0..@min(8, version.len)]);
    @memcpy(s.job.nbits[0..@min(8, nbits.len)], nbits[0..@min(8, nbits.len)]);
    @memcpy(s.job.ntime[0..@min(8, ntime.len)], ntime[0..@min(8, ntime.len)]);
    if (s.job.subsidy == 0) s.job.subsidy = work.subsidy(s.algo[0..s.algo_len], s.height);
    s.job.ready = s.job.coinb1_len > 0;
    s.state = .upstream;
    s.peers = 1;
    note(s, "upstream template. port is open");
    s.height += 1;
}

fn upstreamLoop(index: usize) void {
    const alloc = std.heap.page_allocator;
    var acc: [48 * 1024]u8 = undefined;
    while (true) {
        const s = &slots[index];
        if (!s.used or s.rpc_len > 8 or s.upstream_len < 3) {
            compat.time.sleep(2 * std.time.ns_per_s);
            continue;
        }
        var host_buf: [80]u8 = undefined;
        var port: u16 = 3333;
        const host = hostPort(s.upstream[0..s.upstream_len], &host_buf, &port) orelse {
            s.lock.lock();
            note(s, "bad upstream address");
            s.lock.unlock();
            compat.time.sleep(5 * std.time.ns_per_s);
            continue;
        };
        const stream = connectHost(alloc, host, port) orelse {
            s.lock.lock();
            s.state = .no_node;
            s.job.ready = false;
            note(s, "upstream down");
            s.lock.unlock();
            compat.time.sleep(5 * std.time.ns_per_s);
            continue;
        };
        stream.writeAll("{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"thimble-host\"]}\n{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"thimble.party\",\"x\"]}\n") catch {
            stream.close();
            continue;
        };
        var held: usize = 0;
        while (true) {
            const n = stream.read(acc[held..]) catch break;
            if (n == 0) break;
            held += n;
            var from: usize = 0;
            while (std.mem.indexOfScalarPos(u8, acc[0..held], from, '\n')) |rel| {
                const line = acc[from..rel];
                if (std.mem.indexOf(u8, line, "mining.notify") != null and std.mem.indexOf(u8, line, "method") != null) takeNotify(line, s);
                if (std.mem.indexOf(u8, line, "\"result\"") != null) takeEn1(line, s);
                from = rel + 1;
            }
            if (from > 0 and from <= held) {
                std.mem.copyForwards(u8, acc[0 .. held - from], acc[from..held]);
                held -= from;
            }
            if (held > acc.len - 1024) held = 0;
        }
        stream.close();
        s.lock.lock();
        s.job.ready = false;
        note(s, "upstream dropped. port closed");
        s.lock.unlock();
        compat.time.sleep(3 * std.time.ns_per_s);
    }
}

pub fn forward(port: u16, job: []const u8, en2: []const u8, ntime: []const u8, nonce: []const u8) bool {
    const s = find(port) orelse return false;
    if (s.upstream_len < 3) return false;
    var host_buf: [80]u8 = undefined;
    var up_port: u16 = 3333;
    const host = hostPort(s.upstream[0..s.upstream_len], &host_buf, &up_port) orelse return false;
    const stream = connectHost(std.heap.page_allocator, host, up_port) orelse return false;
    defer stream.close();
    const who = if (s.wallet_len > 0) s.wallet[0..s.wallet_len] else "thimble.party";
    var msg: [500]u8 = undefined;
    const payload = std.fmt.bufPrint(&msg, "{{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"thimble\"]}}\n{{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"{s}\",\"x\"]}}\n{{\"id\":9,\"method\":\"mining.submit\",\"params\":[\"{s}\",\"{s}\",\"{s}\",\"{s}\",\"{s}\"]}}\n", .{ who, who, job, en2, ntime, nonce }) catch return false;
    stream.writeAll(payload) catch return false;
    var buf: [800]u8 = undefined;
    const n = stream.read(&buf) catch return false;
    return std.mem.indexOf(u8, buf[0..n], "\"id\":9") != null and std.mem.indexOf(u8, buf[0..n], "true") != null;
}

fn writeVarint(dst: []u8, n: u64) usize {
    if (dst.len == 0) return 0;
    if (n < 253) {
        dst[0] = @intCast(n);
        return 1;
    }
    if (n <= 0xffff and dst.len >= 3) {
        dst[0] = 253;
        dst[1] = @truncate(n);
        dst[2] = @truncate(n >> 8);
        return 3;
    }
    if (n <= 0xffffffff and dst.len >= 5) {
        dst[0] = 254;
        std.mem.writeInt(u32, dst[1..5], @intCast(n), .little);
        return 5;
    }
    if (dst.len < 9) return 0;
    dst[0] = 255;
    std.mem.writeInt(u64, dst[1..9], n, .little);
    return 9;
}

pub var submit_note: [480]u8 = @splat(0);
pub var submit_note_len: usize = 0;

fn remember(text: []const u8) void {
    const n = @min(text.len, submit_note.len);
    @memcpy(submit_note[0..n], text[0..n]);
    submit_note_len = n;
}

pub fn submitText() []const u8 {
    if (submit_note_len == 0) return "";
    return submit_note[0..submit_note_len];
}

pub fn acceptBlock(port: u16, header: [80]u8, coinbase: []const u8) bool {
    const s = find(port) orelse return false;
    if (s.rpc_len < 8) {
        remember("no rpc");
        return false;
    }
    var path: [40]u8 = undefined;
    const path_s = std.fmt.bufPrint(&path, "jobs/{d}.txs", .{port}) catch return false;
    const alloc = std.heap.page_allocator;
    const txs = compat.fs.cwd().readFileAlloc(alloc, path_s, 8 << 20) catch blk: {
        break :blk alloc.dupe(u8, "") catch return false;
    };
    defer alloc.free(txs);
    var sealed: [1400]u8 = undefined;
    const body = if (work.hasCommitment(coinbase)) work.sealWitness(coinbase, &sealed) orelse {
        remember("segwit coinbase would not seal");
        return false;
    } else coinbase;
    var count: u64 = 1;
    var at: usize = 0;
    while (at + 4 <= txs.len) {
        const len = std.mem.readInt(u32, txs[at .. at + 4][0..4], .little);
        at += 4;
        if (at + len > txs.len) {
            remember("stored transactions are truncated");
            return false;
        }
        at += len;
        count += 1;
    }
    const raw_len = 80 + 9 + body.len + txs.len;
    const raw = alloc.alloc(u8, raw_len) catch return false;
    defer alloc.free(raw);
    @memcpy(raw[0..80], &header);
    var o: usize = 80;
    const vn = writeVarint(raw[o..], count);
    if (vn == 0) {
        remember("transaction count would not encode");
        return false;
    }
    o += vn;
    @memcpy(raw[o .. o + body.len], body);
    o += body.len;
    at = 0;
    while (at + 4 <= txs.len) {
        const len = std.mem.readInt(u32, txs[at .. at + 4][0..4], .little);
        at += 4;
        @memcpy(raw[o .. o + len], txs[at .. at + len]);
        o += len;
        at += len;
    }
    const hex = alloc.alloc(u8, o * 2 + 80) catch return false;
    defer alloc.free(hex);
    const h = work.hexEncode(hex, raw[0..o]);
    const req_buf = alloc.alloc(u8, h.len + 80) catch return false;
    defer alloc.free(req_buf);
    const req = std.fmt.bufPrint(req_buf, "{{\"jsonrpc\":\"1.0\",\"id\":\"s\",\"method\":\"submitblock\",\"params\":[\"{s}\"]}}", .{h}) catch return false;
    const resp = httpPost(alloc, s.rpc[0..s.rpc_len], req) orelse {
        remember("submitblock rpc failed");
        return false;
    };
    defer alloc.free(resp);
    const json = bodyOf(resp);
    const ok = std.mem.indexOf(u8, json, "\"result\":null") != null and std.mem.indexOf(u8, json, "\"error\":null") != null;
    const clip = @min(json.len, submit_note.len);
    remember(json[0..clip]);
    if (ok) s.blocks_found += 1;
    return ok;
}

pub fn acceptAux(port: u16, header: [80]u8, coinbase: []const u8, branch: []const [32]u8) bool {
    const parent = find(port) orelse {
        remember("aux parent slot is gone");
        return false;
    };
    if (parent.job.aux_len != 64 or parent.merge_len < 2) {
        remember("no aux hash in the coinbase. the child node did not return one");
        return false;
    }
    const want = parent.merge[0..parent.merge_len];
    var aux_s: ?*Source = null;
    for (&slots) |*s| {
        if (s.used and s.rpc_len > 8 and std.mem.eql(u8, s.name[0..s.name_len], want)) aux_s = s;
    }
    const aux = aux_s orelse {
        remember("child slot is not configured");
        return false;
    };
    const alloc = std.heap.page_allocator;
    var powb: [8192]u8 = undefined;
    var o: usize = 0;
    if (coinbase.len + 200 + branch.len * 32 > powb.len) {
        remember("aux coinbase does not fit");
        return false;
    }
    @memcpy(powb[o .. o + coinbase.len], coinbase);
    o += coinbase.len;
    // CMerkleTx.hashBlock is the parent block identity, sha256d(header), not the scrypt PoW hash.
    const ph = work.sha256d(&header);
    @memcpy(powb[o .. o + 32], &ph);
    o += 32;
    powb[o] = @intCast(branch.len);
    o += 1;
    for (branch) |b| {
        @memcpy(powb[o .. o + 32], &b);
        o += 32;
    }
    @memset(powb[o .. o + 4], 0);
    o += 4;
    powb[o] = 0;
    o += 1;
    @memset(powb[o .. o + 4], 0);
    o += 4;
    @memcpy(powb[o .. o + 80], &header);
    o += 80;
    const hex = alloc.alloc(u8, o * 2 + 8) catch return false;
    defer alloc.free(hex);
    const h = work.hexEncode(hex, powb[0..o]);
    const req_hex = alloc.alloc(u8, h.len + 220) catch return false;
    defer alloc.free(req_hex);
    const body = std.fmt.bufPrint(req_hex, "{{\"jsonrpc\":\"1.0\",\"id\":\"m\",\"method\":\"submitauxblock\",\"params\":[\"{s}\",\"{s}\"]}}", .{ parent.job.aux_hex[0..parent.job.aux_len], h }) catch {
        remember("submitauxblock request would not fit");
        return false;
    };
    const resp = httpPost(alloc, aux.rpc[0..aux.rpc_len], body) orelse {
        remember("submitauxblock rpc failed");
        return false;
    };
    defer alloc.free(resp);
    const json = bodyOf(resp);
    remember(json[0..@min(json.len, submit_note.len)]);
    return std.mem.indexOf(u8, json, "\"result\":true") != null;
}

var node_arg: [8][3][260]u8 = undefined;
var node_len: [8][3]usize = undefined;
var node_argv: [8][3][]const u8 = undefined;
var node_live: [8]bool = .{ false, false, false, false, false, false, false, false };

fn findDaemon(dir: []const u8, out: []u8) ?[]u8 {
    const names = [_][]const u8{ "bitcoind.exe", "litecoind.exe", "dogecoind.exe", "bitcoind", "litecoind", "dogecoind" };
    const roots = [_][]const u8{ "bin/", "src/", "build/src/", "build/bin/", "" };
    for (roots) |root| {
        for (names) |name| {
            var path: [300]u8 = undefined;
            const p = std.fmt.bufPrint(&path, "{s}/{s}{s}", .{ dir, root, name }) catch continue;
            if (compat.fs.cwd().access(p, .{})) |_| {
                const n = @min(out.len, p.len);
                @memcpy(out[0..n], p[0..n]);
                return out[0..n];
            } else |_| {}
        }
    }
    return null;
}

fn rpcPort(name: []const u8, index: usize) u16 {
    if (std.mem.eql(u8, name, "Bitcoin")) return 8332;
    if (std.mem.eql(u8, name, "Litecoin")) return 9332;
    if (std.mem.eql(u8, name, "Dogecoin")) return 22555;
    return @intCast(18440 + index);
}

pub fn launchBinary(port: u16, algo: []const u8, name: []const u8, bin: []const u8) void {
    spawnNode(port, algo, name, bin);
}

pub fn launchBuilt(port: u16, algo: []const u8, name: []const u8, dir: []const u8) void {
    var binbuf: [260]u8 = undefined;
    const bin = findDaemon(dir, &binbuf) orelse {
        setStage("failed", "the build finished but no node binary was found");
        const s = forPort(port);
        s.lock.lock();
        note(s, "no node binary");
        s.lock.unlock();
        return;
    };
    spawnNode(port, algo, name, bin);
}

fn spawnNode(port: u16, algo: []const u8, name: []const u8, bin: []const u8) void {
    const s = forPort(port);
    s.algo_len = put(&s.algo, algo);
    s.name_len = put(&s.name, name);
    var index: usize = 0;
    for (&slots, 0..) |*slot, i| {
        if (slot == s) index = i;
    }
    if (node_live[index]) {
        setStage("connecting", "node is already running");
        return;
    }
    var data: [200]u8 = undefined;
    const data_s = std.fmt.bufPrint(&data, "coin-data/{s}", .{name}) catch return;
    compat.fs.cwd().makePath(data_s) catch return;
    var pass: [16]u8 = undefined;
    const stamp: u64 = @intCast(@max(compat.time.timestamp(), 1));
    _ = std.fmt.bufPrint(&pass, "{x:0>16}", .{stamp}) catch return;
    const rpc = rpcPort(name, index);
    var conf_path: [240]u8 = undefined;
    const conf = std.fmt.bufPrint(&conf_path, "{s}/coin.conf", .{data_s}) catch return;
    var cf = compat.fs.cwd().createFile(conf, .{}) catch return;
    cf.print("server=1\nrpcuser=thimble\nrpcpassword={s}\nrpcport={d}\nrpcbind=127.0.0.1\nrpcallowip=127.0.0.1\n", .{ pass[0..16], rpc }) catch {};
    if (!std.mem.eql(u8, name, "Dogecoin")) cf.print("prune=550\n", .{}) catch {};
    cf.print("listen=1\n", .{}) catch {};
    cf.close();
    var url: [160]u8 = undefined;
    const url_s = std.fmt.bufPrint(&url, "http://thimble:{s}@127.0.0.1:{d}", .{ pass[0..16], rpc }) catch return;
    var url_keep: [160]u8 = undefined;
    const url_n = @min(url_s.len, url_keep.len);
    @memcpy(url_keep[0..url_n], url_s[0..url_n]);
    node_len[index][0] = put(&node_arg[index][0], bin);
    var arg1: [240]u8 = undefined;
    const a1 = std.fmt.bufPrint(&arg1, "-datadir={s}", .{data_s}) catch return;
    node_len[index][1] = put(&node_arg[index][1], a1);
    var arg2: [260]u8 = undefined;
    const a2 = std.fmt.bufPrint(&arg2, "-conf={s}", .{conf}) catch return;
    node_len[index][2] = put(&node_arg[index][2], a2);
    node_argv[index][0] = node_arg[index][0][0..node_len[index][0]];
    node_argv[index][1] = node_arg[index][1][0..node_len[index][1]];
    node_argv[index][2] = node_arg[index][2][0..node_len[index][2]];
    var err_path: [260]u8 = undefined;
    const err_s = std.fmt.bufPrint(&err_path, "{s}/node.err", .{data_s}) catch return;
    const err_file = std.Io.Dir.cwd().createFile(compat.io, err_s, .{}) catch null;
    var child = compat.Child.init(node_argv[index][0..3], std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    if (err_file) |f| child.stderr_file = f;
    child.create_no_window = true;
    child.spawn() catch {
        setStage("failed", "the node binary would not start");
        return;
    };
    node_live[index] = true;
    setFeed(port, algo, url_keep[0..url_n]);
    s.wallet_len = walletFrom(port, &s.wallet);
    setStage("connecting", "node process started. waiting for rpc");
    var up = false;
    var tick: usize = 0;
    while (tick < 20) : (tick += 1) {
        compat.time.sleep(std.time.ns_per_s);
        if (httpPost(std.heap.page_allocator, url_keep[0..url_n], "{\"jsonrpc\":\"1.0\",\"id\":\"w\",\"method\":\"getblockchaininfo\",\"params\":[]}")) |ping| {
            std.heap.page_allocator.free(ping);
            up = true;
            break;
        }
    }
    if (!up) {
        var why: [160]u8 = undefined;
        const detail = fileTail(err_s, &why);
        const debug_path = std.fmt.bufPrint(&err_path, "{s}/debug.log", .{data_s}) catch err_s;
        const debug = if (detail.len == 0) fileTail(debug_path, &why) else detail;
        setStage("failed", if (debug.len > 0) debug else "node did not answer rpc. see coin-data node.err");
        return;
    }
    setStage("syncing", "node started. miners can connect. work starts when a template exists");
    s.lock.lock();
    note(s, "node started, waiting for the chain");
    s.lock.unlock();
    ensureWallet(s, url_keep[0..url_n]);
}

fn fileTail(path: []const u8, out: []u8) []const u8 {
    const raw = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 16) catch return "";
    defer std.heap.page_allocator.free(raw);
    var end = raw.len;
    while (end > 0 and (raw[end - 1] == '\n' or raw[end - 1] == '\r' or raw[end - 1] == ' ')) end -= 1;
    if (end == 0) return "";
    var from = end;
    while (from > 0 and raw[from - 1] != '\n' and raw[from - 1] != '\r') from -= 1;
    const line = raw[from..end];
    const n = @min(line.len, out.len);
    @memcpy(out[0..n], line[0..n]);
    return out[0..n];
}

fn ensureWallet(s: *Source, url: []const u8) void {
    var script: [80]u8 = undefined;
    if (s.wallet_len > 0 and work.outputScript(s.wallet[0..s.wallet_len], &script) != null) return;
    const alloc = std.heap.page_allocator;
    var tries: usize = 0;
    while (tries < 40) : (tries += 1) {
        compat.time.sleep(3 * std.time.ns_per_s);
        const ping = httpPost(alloc, url, "{\"jsonrpc\":\"1.0\",\"id\":\"w\",\"method\":\"getblockchaininfo\",\"params\":[]}") orelse continue;
        alloc.free(ping);
        if (httpPost(alloc, url, "{\"jsonrpc\":\"1.0\",\"id\":\"c\",\"method\":\"createwallet\",\"params\":[\"thimble\"]}")) |made| alloc.free(made);
        const raw = httpPost(alloc, url, "{\"jsonrpc\":\"1.0\",\"id\":\"a\",\"method\":\"getnewaddress\",\"params\":[\"pool\",\"bech32\"]}") orelse continue;
        defer alloc.free(raw);
        var addr: [90]u8 = undefined;
        const n = copyField(bodyOf(raw), "result", &addr);
        if (n < 14) continue;
        if (work.outputScript(addr[0..n], &script) == null) continue;
        s.wallet_len = put(&s.wallet, addr[0..n]);
        setStage("syncing", "payout address is set. the pool port opens when a template exists");
        return;
    }
    setStage("syncing", "node is up. it has not given a payout address yet");
}

fn walletFrom(port: u16, dst: []u8) usize {
    const raw = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, "pools.cfg", 1 << 16) catch return 0;
    defer std.heap.page_allocator.free(raw);
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |row| {
        if (row.len < 2 or row[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, row, '\t');
        _ = parts.next();
        _ = parts.next();
        const p = std.fmt.parseInt(u16, parts.next() orelse "0", 10) catch 0;
        _ = parts.next();
        _ = parts.next();
        _ = parts.next();
        _ = parts.next();
        const wal = parts.next() orelse "";
        if (p == port and wal.len > 0) return put(dst, wal);
    }
    return 0;
}

pub fn sendTo(port: u16, address: []const u8, sats: u64) ?[]u8 {
    const s = find(port) orelse return null;
    if (s.rpc_len < 8 or sats == 0) return null;
    const whole = sats / 100_000_000;
    const frac = sats % 100_000_000;
    var body: [320]u8 = undefined;
    const req = std.fmt.bufPrint(&body, "{{\"jsonrpc\":\"1.0\",\"id\":\"pay\",\"method\":\"sendtoaddress\",\"params\":[\"{s}\",\"{d}.{d:0>8}\",\"\",\"\",false,false,null,\"unset\",false,1]}}", .{ address, whole, frac }) catch return null;
    return httpPost(std.heap.page_allocator, s.rpc[0..s.rpc_len], req);
}

pub fn snapshot(port: u16) Job {
    const s = find(port) orelse return .{};
    s.lock.lock();
    defer s.lock.unlock();
    return s.job;
}

pub fn refresh(port: u16) void {
    const s = find(port) orelse return;
    if (s.rpc_len > 8) pollRpc(s, std.heap.page_allocator);
}

pub fn mergeOf(port: u16) ?struct { port: u16, height: u32 } {
    const parent = find(port) orelse return null;
    if (parent.merge_len < 2 or std.mem.eql(u8, parent.merge[0..parent.merge_len], "none")) return null;
    const want = parent.merge[0..parent.merge_len];
    for (&slots) |*s| {
        if (s.used and std.mem.eql(u8, s.name[0..s.name_len], want)) return .{ .port = s.port, .height = s.chain_tip };
    }
    return null;
}

pub fn tip(port: u16) u32 {
    const s = find(port) orelse return 0;
    s.lock.lock();
    defer s.lock.unlock();
    return s.chain_tip;
}
