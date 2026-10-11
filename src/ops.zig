const chain = @import("chain.zig");
const compat = @import("compat.zig");
const modules = @import("modules.zig");
const party = @import("party.zig");
const std = @import("std");
const work = @import("work.zig");

pub const Grade = enum { pass, warn, fail };

pub const Finding = struct {
    grade: Grade = .pass,
    name: [40]u8 = @splat(0),
    name_len: usize = 0,
    detail: [200]u8 = @splat(0),
    detail_len: usize = 0,
};

pub const Report = struct {
    items: [48]Finding = @splat(.{}),
    n: usize = 0,
    pass_n: u16 = 0,
    warn_n: u16 = 0,
    fail_n: u16 = 0,
};

pub const Opts = struct {
    probe: bool = false,
    config: bool = true,
    live: bool = true,
    files: bool = true,
    expect_signon: bool = false,
    expect_listen: bool = false,
};

const Trace = struct {
    at: i64 = 0,
    port: u16 = 0,
    worker: [48]u8 = @splat(0),
    worker_len: usize = 0,
    kind: [24]u8 = @splat(0),
    kind_len: usize = 0,
    why: [96]u8 = @splat(0),
    why_len: usize = 0,
};

const Tally = struct {
    seen: u64 = 0,
    share: u64 = 0,
    block: u64 = 0,
    unconfirmed: u64 = 0,
    low: u64 = 0,
    stale: u64 = 0,
    bad: u64 = 0,
    algo: u64 = 0,
    other: u64 = 0,
};

var traces: [24]Trace = @splat(.{});
var trace_at: usize = 0;
var trace_len: usize = 0;
var tally: Tally = .{};
var trace_lock: compat.Mutex = .{};
var head_buf: [160]u8 = @splat(0);
var head_len: usize = 0;

fn hex8(v: u32, out: *[8]u8) []const u8 {
    const digits = "0123456789abcdef";
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const shift: u5 = @intCast((7 - i) * 4);
        out[i] = digits[(v >> shift) & 0xf];
    }
    return out;
}

fn put(dst: []u8, src: []const u8) usize {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

pub fn noteShare(port: u16, worker: []const u8, kind: []const u8, why: []const u8) void {
    trace_lock.lock();
    defer trace_lock.unlock();
    tally.seen += 1;
    if (std.mem.eql(u8, kind, "share")) tally.share += 1 else if (std.mem.eql(u8, kind, "block")) tally.block += 1 else if (std.mem.eql(u8, kind, "block-unconfirmed")) tally.unconfirmed += 1 else if (std.mem.eql(u8, kind, "low")) tally.low += 1 else if (std.mem.eql(u8, kind, "stale")) tally.stale += 1 else if (std.mem.eql(u8, kind, "bad")) tally.bad += 1 else if (std.mem.eql(u8, kind, "algo")) tally.algo += 1 else tally.other += 1;
    const slot = &traces[trace_at];
    slot.* = .{};
    slot.at = compat.time.timestamp();
    slot.port = port;
    slot.worker_len = put(&slot.worker, worker);
    slot.kind_len = put(&slot.kind, kind);
    slot.why_len = put(&slot.why, why);
    trace_at = (trace_at + 1) % traces.len;
    if (trace_len < traces.len) trace_len += 1;
}

pub fn headline() []const u8 {
    if (head_len == 0) return "not run. Press Check this host, or run ./thimble --check";
    return head_buf[0..head_len];
}

fn remember(report: *const Report) void {
    const ready = if (report.fail_n == 0) "ready" else "NOT READY";
    const text = std.fmt.bufPrint(&head_buf, "{s}   {d} pass   {d} warn   {d} fail", .{ ready, report.pass_n, report.warn_n, report.fail_n }) catch "check failed to format";
    head_len = text.len;
}

fn add(r: *Report, grade: Grade, name: []const u8, detail: []const u8) void {
    if (r.n >= r.items.len) return;
    const f = &r.items[r.n];
    r.n += 1;
    f.grade = grade;
    f.name_len = put(&f.name, name);
    f.detail_len = put(&f.detail, detail);
    switch (grade) {
        .pass => r.pass_n += 1,
        .warn => r.warn_n += 1,
        .fail => r.fail_n += 1,
    }
}

fn addf(r: *Report, grade: Grade, name: []const u8, comptime fmt: []const u8, args: anytype) void {
    var buf: [200]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch "detail did not fit";
    add(r, grade, name, text);
}

fn app(buf: []u8, n: *usize, text: []const u8) void {
    if (n.* >= buf.len) return;
    const c = @min(text.len, buf.len - n.*);
    @memcpy(buf[n.*..][0..c], text[0..c]);
    n.* += c;
}

pub fn format(buf: []u8, report: *const Report) usize {
    var n: usize = 0;
    var line: [240]u8 = undefined;
    const ready = if (report.fail_n == 0) "READY" else "NOT READY";
    const head = std.fmt.bufPrint(&line, "thimble check  {s}  pass {d}  warn {d}  fail {d}\n", .{ ready, report.pass_n, report.warn_n, report.fail_n }) catch "thimble check\n";
    app(buf, &n, head);
    for (report.items[0..report.n]) |f| {
        const tag = switch (f.grade) {
            .pass => "PASS",
            .warn => "WARN",
            .fail => "FAIL",
        };
        const row = std.fmt.bufPrint(&line, "{s}  {s}  {s}\n", .{ tag, f.name[0..f.name_len], f.detail[0..f.detail_len] }) catch continue;
        app(buf, &n, row);
    }
    app(buf, &n, "--- recent shares ---\n");
    trace_lock.lock();
    const seen = tally.seen;
    const row = std.fmt.bufPrint(&line, "seen {d}  share {d}  block {d}  unconfirmed {d}  low {d}  stale {d}  bad {d}  algo {d}  other {d}\n", .{
        tally.seen, tally.share, tally.block, tally.unconfirmed, tally.low, tally.stale, tally.bad, tally.algo, tally.other,
    }) catch "seen\n";
    app(buf, &n, row);
    if (seen == 0) {
        app(buf, &n, "no miner has submitted a share to this process\n");
    } else {
        const show = @min(trace_len, 12);
        const start = trace_len - show;
        const now = compat.time.timestamp();
        var i: usize = start;
        while (i < trace_len) : (i += 1) {
            const idx = if (trace_len < traces.len) i else (trace_at + i) % traces.len;
            const t = traces[idx];
            const ago: i64 = if (now > t.at) now - t.at else 0;
            const one = std.fmt.bufPrint(&line, "{d}s ago  port {d}  {s}  {s}  {s}\n", .{ ago, t.port, t.worker[0..t.worker_len], t.kind[0..t.kind_len], t.why[0..t.why_len] }) catch continue;
            app(buf, &n, one);
        }
    }
    trace_lock.unlock();
    return n;
}

fn revHex(hash: [32]u8, out: []u8) []const u8 {
    var rev: [32]u8 = undefined;
    for (0..32) |i| rev[i] = hash[31 - i];
    return work.hexEncode(out, &rev);
}

fn checkMath(alloc: std.mem.Allocator, r: *Report) void {
    const genesis = "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c";
    var raw: [80]u8 = undefined;
    const decoded = work.hexDecode(&raw, genesis);
    if (decoded == null or decoded.?.len != 80) {
        add(r, .fail, "hash.genesis", "the bitcoin genesis header did not decode");
    } else {
        var show: [64]u8 = undefined;
        const hex = revHex(work.sha256d(decoded.?), &show);
        if (std.mem.eql(u8, hex, "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")) {
            add(r, .pass, "hash.genesis", "double-sha256 of the bitcoin genesis header matches");
        } else addf(r, .fail, "hash.genesis", "got {s}, not the bitcoin genesis hash. share checks are wrong", .{hex});
    }

    const litecoin = "010000000000000000000000000000000000000000000000000000000000000000000000d9ced4ed1130f7b7faad9be25323ffafa33232a17c3edf6cfd97bee6bafbdd97b9aa8e4ef0ff0f1ecd513f7c";
    var lraw: [80]u8 = undefined;
    if (work.hexDecode(&lraw, litecoin)) |body| {
        if (work.scrypt1024(alloc, body)) |hash| {
            var again = work.scrypt1024(alloc, body) catch hash;
            var show: [64]u8 = undefined;
            const hex = revHex(hash, &show);
            if (!std.mem.eql(u8, &hash, &again)) {
                add(r, .fail, "hash.scrypt", "scrypt of the same header changed. shares would flap");
            } else if (!std.mem.eql(u8, hex, "0000050c34a64b415b6b15b37f2216634b5b1669cb9a2e38d76f7213b0671e00")) {
                addf(r, .fail, "hash.scrypt", "litecoin genesis proof is {s}. shares would not match the coin", .{hex});
            } else {
                var id_buf: [64]u8 = undefined;
                const id = revHex(work.sha256d(body), &id_buf);
                if (!std.mem.eql(u8, id, "12a765e31ffd4059bada1e25190f6e98c99d9714d334efa41a195a7e7e04bfe2")) {
                    add(r, .fail, "hash.scrypt", "the header is not the litecoin genesis block");
                } else add(r, .pass, "hash.scrypt", "litecoin genesis scrypt matches, and its block id is the published one");
            }
        } else |_| add(r, .fail, "hash.scrypt", "scrypt returned an error on an 80-byte header");
    } else add(r, .fail, "hash.scrypt", "litecoin genesis header did not decode");

    var easy_ok = false;
    var easy_bad: []const u8 = "";
    var nonce_i: u32 = 0;
    while (nonce_i < 64) : (nonce_i += 1) {
        var nonce_hex: [8]u8 = undefined;
        const nonce = hex8(nonce_i, &nonce_hex);
        const easy = work.check(alloc, "sha256d", "01000000", "0000000000000000000000000000000000000000000000000000000000000000", "00", "00", "00", "00", &.{}, "29ab5f49", "207fffff", nonce, 1, true);
        if (easy.verdict == .block or easy.verdict == .share) {
            easy_ok = true;
            break;
        }
        if (easy.verdict == .bad or easy.verdict == .algo or easy.verdict == .no_job) {
            easy_bad = @tagName(easy.verdict);
            break;
        }
    }
    if (easy_bad.len != 0) {
        addf(r, .fail, "share.easy", "a regtest header was {s}. the checker rejected a well-formed job", .{easy_bad});
    } else if (easy_ok) {
        add(r, .pass, "share.easy", "a regtest-difficulty header is accepted as work");
    } else add(r, .fail, "share.easy", "none of 64 regtest headers met bits 207fffff. targets are wrong");

    const hard = work.check(alloc, "sha256d", "01000000", "0000000000000000000000000000000000000000000000000000000000000000", "00", "00", "00", "00", &.{}, "29ab5f49", "1d00ffff", "00000000", 1024, true);
    if (hard.verdict == .bad or hard.verdict == .algo or hard.verdict == .no_job) {
        addf(r, .fail, "share.hard", "a well-formed hard header was {s}, not a low share", .{@tagName(hard.verdict)});
    } else addf(r, .pass, "share.hard", "genesis-difficulty header is {s}, not silently accepted", .{@tagName(hard.verdict)});

    const other = work.check(alloc, "ethash", "01000000", "0000000000000000000000000000000000000000000000000000000000000000", "00", "00", "00", "00", &.{}, "29ab5f49", "207fffff", "00000000", 1, true);
    const none = work.check(alloc, "sha256d", "01000000", "0000000000000000000000000000000000000000000000000000000000000000", "00", "00", "00", "00", &.{}, "29ab5f49", "207fffff", "00000000", 1, false);
    const junk = work.check(alloc, "scrypt", "01000000", "0000000000000000000000000000000000000000000000000000000000000000", "zz", "00", "00", "00", &.{}, "29ab5f49", "207fffff", "00000000", 1, true);
    if (other.verdict != .algo or none.verdict != .no_job or junk.verdict != .bad) {
        addf(r, .fail, "share.reject", "ethash={s} no-job={s} bad-hex={s}. refusals must stay specific", .{ @tagName(other.verdict), @tagName(none.verdict), @tagName(junk.verdict) });
    } else add(r, .pass, "share.reject", "ethash is refused, a missing template is refused, bad hex is refused");

    const wide = work.diff1();
    const tight = work.divide(wide, 1024);
    if (std.mem.eql(u8, &wide, &tight)) {
        add(r, .fail, "share.vardiff", "dividing the target by 1024 did nothing. vardiff cannot tighten");
    } else add(r, .pass, "share.vardiff", "a higher difficulty is a tighter target");

    const era0 = work.subsidy("sha256d", 0);
    const era1 = work.subsidy("sha256d", 210_000);
    const scrypt0 = work.subsidy("scrypt", 0);
    const other_pay = work.subsidy("kawpow", 1);
    if (era0 != 5_000_000_000 or era1 != 2_500_000_000 or scrypt0 != 5_000_000_000 or other_pay != 0 or era0 == 1_000_000) {
        addf(r, .fail, "pay.subsidy", "sha256d height 0 is {d}, not 50 BTC. unchecked algos pay {d}", .{ era0, other_pay });
    } else add(r, .pass, "pay.subsidy", "bitcoin subsidy is 50 BTC then 25. an unchecked algo pays nothing");

    var cuts: [2]u64 = undefined;
    const part = party.divideReward(5_000_000_000, &.{ 60, 40 }, &cuts);
    if (part.house != 50_000_000 or cuts[0] != 2_970_000_000 or cuts[1] != 1_980_000_000 or part.paid + part.house != 5_000_000_000) {
        addf(r, .fail, "pay.party", "60/40 of 50 BTC paid {d}+{d}, house {d}", .{ cuts[0], cuts[1], part.house });
    } else {
        var zero: [1]u64 = undefined;
        const empty = party.divideReward(5_000_000_000, &.{0}, &zero);
        if (empty.paid != 0 or zero[0] != 0) {
            add(r, .fail, "pay.party", "a round with no shares still paid someone");
        } else add(r, .pass, "pay.party", "1% house, the rest by round shares, nothing if the round is empty");
    }

    if (work.matured(100, 100) or !work.matured(199, 100)) {
        add(r, .fail, "pay.mature", "balances would spend before 100 confirmations");
    } else add(r, .pass, "pay.mature", "a block credit waits until 100 confirmations");

    var script: [40]u8 = undefined;
    const base = work.outputScript("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", &script);
    const bech = work.outputScript("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", &script);
    const garbage = work.outputScript("thimble", &script);
    if (base == null or bech == null or garbage != null) {
        add(r, .fail, "pay.address", "base58 or bc1 decoding is wrong, so sends would go nowhere or anywhere");
    } else add(r, .pass, "pay.address", "base58 and bc1 decode. a plain word does not");
}

fn checkFiles(r: *Report) void {
    var file = compat.fs.cwd().createFile("ops-check.tmp", .{}) catch {
        add(r, .fail, "files.write", "cannot create ops-check.tmp beside the host. party.db and payouts.cfg will not save");
        return;
    };
    file.writeAll("ok\n") catch {
        file.close();
        add(r, .fail, "files.write", "the disk accepted the file and then refused the write");
        return;
    };
    file.close();
    compat.fs.cwd().rename("ops-check.tmp", "ops-check.ok") catch {
        add(r, .fail, "files.write", "rename failed. a crash mid-save would leave a torn party.db");
        return;
    };
    add(r, .pass, "files.write", "atomic rename works. party.db, payouts.cfg, and the ledgers can save");
}

fn envOf(alloc: std.mem.Allocator, name: []const u8) ?[]u8 {
    return compat.getEnv(alloc, name) catch null;
}

fn checkEnv(alloc: std.mem.Allocator, r: *Report) void {
    if (envOf(alloc, "THIMBLE_ADMIN")) |v| {
        defer alloc.free(v);
        if (v.len < 8) {
            add(r, .fail, "env.admin", "THIMBLE_ADMIN is shorter than 8. the admin page refuses it");
        } else add(r, .pass, "env.admin", "admin token is set, from the environment or host.cfg");
    } else add(r, .warn, "env.admin", "no admin token in the environment or host.cfg. /admin will refuse every coin fetch");

    if (envOf(alloc, "THIMBLE_PAY_SATS")) |v| {
        defer alloc.free(v);
        const n = std.fmt.parseInt(u64, v, 10) catch 0;
        if (n == 0) {
            add(r, .fail, "env.pay", "THIMBLE_PAY_SATS is not a positive number. payouts will not send");
        } else addf(r, .pass, "env.pay", "a balance sends at {d} sats, once the worker name is an address", .{n});
    } else add(r, .pass, "env.pay", "payout threshold is the default 100000 sats");

    const rpc = envOf(alloc, "THIMBLE_RPC");
    const up = envOf(alloc, "THIMBLE_UPSTREAM");
    defer if (rpc) |v| alloc.free(v);
    defer if (up) |v| alloc.free(v);
    const has_rpc = if (rpc) |v| v.len > 8 else false;
    const has_up = if (up) |v| v.len > 3 else false;
    if (has_rpc and has_up) {
        add(r, .fail, "env.source", "THIMBLE_RPC and THIMBLE_UPSTREAM are both set. one chain source per module. the second feed replaces the first");
    } else if (has_rpc or has_up) add(r, .pass, "env.source", "one chain source is set in the environment");
}

const Row = struct {
    name: []const u8,
    algo: []const u8,
    port: u16,
    on: bool,
    merge: []const u8,
    bonus: u8,
    source: []const u8,
    wallet: []const u8,
    line_no: u32,
    house: bool = false,
};

fn checkConfig(alloc: std.mem.Allocator, r: *Report) void {
    checkEnv(alloc, r);
    const raw = compat.fs.cwd().readFileAlloc(alloc, "pools.cfg", 1 << 16) catch {
        add(r, .warn, "config.file", "no pools.cfg. Settings has not saved a module. the host will not listen on a pool port");
        return;
    };
    defer alloc.free(raw);
    var rows: [8]Row = undefined;
    var rn: usize = 0;
    var house = false;
    var line_no: u32 = 0;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        line_no += 1;
        if (line.len < 2) continue;
        if (line[0] == '#') {
            if (std.mem.indexOf(u8, line, "house") != null) house = std.mem.indexOf(u8, line, "1") != null;
            continue;
        }
        var parts = std.mem.splitScalar(u8, line, '\t');
        const name = parts.next() orelse continue;
        if (std.mem.eql(u8, name, "house") or std.mem.eql(u8, name, "data")) continue;
        const algo = parts.next() orelse {
            addf(r, .fail, "config.row", "line {d} has a name and nothing else", .{line_no});
            continue;
        };
        const port_s = parts.next() orelse {
            addf(r, .fail, "config.row", "line {d} needs a port", .{line_no});
            continue;
        };
        const on_s = parts.next() orelse {
            addf(r, .fail, "config.row", "line {d} needs the on column, 1 or 0", .{line_no});
            continue;
        };
        if (rn >= rows.len) {
            add(r, .fail, "config.row", "more than 8 modules. the rest are ignored");
            continue;
        }
        rows[rn] = .{
            .name = name,
            .algo = algo,
            .port = std.fmt.parseInt(u16, port_s, 10) catch 0,
            .on = std.mem.eql(u8, on_s, "1"),
            .merge = parts.next() orelse "",
            .bonus = std.fmt.parseInt(u8, parts.next() orelse "0", 10) catch 0,
            .source = parts.next() orelse "",
            .wallet = parts.next() orelse "",
            .line_no = line_no,
            .house = house,
        };
        rn += 1;
    }
    if (rn == 0) add(r, .warn, "config.modules", "pools.cfg has no module. add one in Settings");
    var running: usize = 0;
    for (rows[0..rn]) |row| {
        if (!row.on) continue;
        running += 1;
        var label: [40]u8 = undefined;
        const name = std.fmt.bufPrint(&label, "module.{s}", .{row.name}) catch "module";
        if (row.port == 0) add(r, .fail, name, "port is 0. nothing can listen");
        if (work.checkedAlgo(row.algo) == null) {
            addf(r, .fail, name, "{s} is not checked. every share on port {d} is refused with 'algorithm not checked yet'", .{ row.algo, row.port });
        } else addf(r, .pass, name, "{s} on port {d} is an algorithm this pool can check", .{ row.algo, row.port });
        if (row.source.len == 0) {
            add(r, .warn, name, "no jobs. use External pool host:port, or http://user:pass@127.0.0.1:8332, or build the coin and wait for its node");
        } else if (std.mem.startsWith(u8, row.source, "https://") or std.mem.indexOf(u8, row.source, "github.com") != null) {
            add(r, .fail, name, "the jobs field is a codebase URL. that does not serve work. Build and open pool, and leave External pool empty unless you have a backup");
        } else if (std.mem.startsWith(u8, row.source, "http://") and std.mem.indexOfScalar(u8, row.source, '@') == null) {
            add(r, .fail, name, "rpc URL needs http://user:pass@host:port. without the user the node will not answer");
        } else add(r, .pass, name, "jobs come from one pool or one node, not from a git URL");
        if (row.wallet.len == 0) {
            add(r, .warn, name, "no coinbase address. a node template needs the Wallet field. workers are paid when their name is an address");
        } else {
            var script: [80]u8 = undefined;
            if (work.outputScript(row.wallet, &script) == null) {
                addf(r, .fail, name, "wallet '{s}' is not base58 or bc1. coinbase and sendtoaddress will fail", .{row.wallet});
            } else add(r, .pass, name, "wallet decodes. coinbase can pay it");
        }
        if (row.bonus > 0 and !house) addf(r, .warn, name, "bonus is {d}% but house mines is off, so no bonus accumulates", .{row.bonus});
        if (row.bonus > 100) add(r, .fail, name, "bonus is over 100%. that is not a percent of the house shares");
        const merge = row.merge;
        if (merge.len > 0 and !std.mem.eql(u8, merge, "none") and !std.mem.eql(u8, merge, "0")) {
            var child: ?Row = null;
            for (rows[0..rn]) |other| {
                if (std.mem.eql(u8, other.name, merge)) child = other;
            }
            if (child == null) {
                addf(r, .warn, name, "merge-mine {s} is not a saved module. it will not pay a second subsidy", .{merge});
            } else if (child.?.port == row.port) {
                addf(r, .fail, name, "merge child {s} is on the same port. it needs its own module and its own chain source", .{merge});
            } else if (!child.?.on) {
                addf(r, .warn, name, "merge child {s} is saved but stopped", .{merge});
            } else if (child.?.source.len == 0) {
                addf(r, .warn, name, "merge child {s} has no chain source of its own", .{merge});
            } else addf(r, .pass, name, "merge child {s} is its own module on port {d}", .{ merge, child.?.port });
        }
        for (rows[0..rn]) |other| {
            if (other.line_no <= row.line_no or other.port != row.port or !other.on) continue;
            if (row.source.len > 0 and other.source.len > 0 and !std.mem.eql(u8, row.source, other.source)) {
                addf(r, .fail, name, "port {d} has two chain sources. one module, one source", .{row.port});
            } else addf(r, .warn, name, "port {d} is also used by {s}. only one listener can bind", .{ row.port, other.name });
        }
    }
    if (running == 0 and rn > 0) add(r, .warn, "config.modules", "every module is stopped. start one to open a port");
    if (house and running == 0) add(r, .warn, "config.house", "house mines is on, but no module is running to mine toward");
}

const Snap = struct {
    port: u16,
    ready: bool,
    height: u32,
    subsidy: u64,
    state: chain.State,
    peers: u32,
    ibd: bool,
    err: [160]u8 = @splat(0),
    err_len: usize = 0,
    ntime: [8]u8 = @splat(0),
    nbits: [8]u8 = @splat(0),
    coinb1_len: usize = 0,
    en1_len: usize = 0,
    rpc: [180]u8 = @splat(0),
    rpc_len: usize = 0,
    upstream: [96]u8 = @splat(0),
    upstream_len: usize = 0,
    name: [32]u8 = @splat(0),
    name_len: usize = 0,
};

fn takeSnap(s: *chain.Source) Snap {
    s.lock.lock();
    defer s.lock.unlock();
    var snap = Snap{
        .port = s.port,
        .ready = s.job.ready,
        .height = s.height,
        .subsidy = s.job.subsidy,
        .state = s.state,
        .peers = s.peers,
        .ibd = s.ibd,
        .coinb1_len = s.job.coinb1_len,
        .en1_len = s.job.en1_len,
    };
    snap.err_len = put(&snap.err, s.err[0..s.err_len]);
    @memcpy(snap.ntime[0..8], s.job.ntime[0..8]);
    @memcpy(snap.nbits[0..8], s.job.nbits[0..8]);
    snap.rpc_len = put(&snap.rpc, s.rpc[0..s.rpc_len]);
    snap.upstream_len = put(&snap.upstream, s.upstream[0..s.upstream_len]);
    snap.name_len = put(&snap.name, s.name[0..s.name_len]);
    return snap;
}

fn checkLive(r: *Report) void {
    var any = false;
    for (&chain.slots) |*s| {
        if (!s.used) continue;
        any = true;
        const snap = takeSnap(s);
        var label: [40]u8 = undefined;
        const who = if (snap.name_len > 0) snap.name[0..snap.name_len] else "slot";
        const name = std.fmt.bufPrint(&label, "live.{s}", .{who}) catch "live";
        if (snap.rpc_len > 8 and snap.upstream_len > 3) {
            add(r, .fail, name, "this module has both an rpc node and an upstream pool. keep one");
        }
        if (!snap.ready) {
            const why = if (snap.err_len > 0) snap.err[0..snap.err_len] else "no feed attached";
            if (snap.ibd) {
                addf(r, .warn, name, "node is downloading. height {d}. the port stays closed until getblocktemplate works. a pruned node is enough. an upstream pool skips the download. {s}", .{ snap.height, why });
            } else addf(r, .warn, name, "no template yet ({s}). port {d} stays closed. {s}", .{ @tagName(snap.state), snap.port, why });
            continue;
        }
        if (snap.coinb1_len == 0 or snap.en1_len < 4) {
            add(r, .fail, name, "template is marked ready but the coinbase or extranonce is empty. miners cannot build a header");
            continue;
        }
        if (work.targetFromBits(snap.nbits[0..8]) == null) {
            add(r, .fail, name, "template nbits are not a compact target. every share would be a bad share");
            continue;
        }
        if (snap.subsidy == 0) add(r, .warn, name, "template subsidy is 0. a found block would pay the party nothing");
        const ntime = std.fmt.parseInt(u32, snap.ntime[0..8], 16) catch 0;
        const now_i = compat.time.timestamp();
        const now: u32 = if (now_i > 0) @intCast(@min(now_i, std.math.maxInt(u32))) else 0;
        if (ntime == 0) {
            add(r, .warn, name, "template ntime is zero. miners will stale immediately");
        } else {
            const delta: u32 = if (ntime > now) ntime - now else now - ntime;
            if (delta > 2 * 3600) addf(r, .warn, name, "template time is {d} seconds off this clock. shares will be stale", .{delta});
        }
        if (snap.peers == 0 and snap.state != .upstream) {
            addf(r, .warn, name, "template is live at height {d} but the node has zero peers. a block you find may not relay", .{snap.height});
        }
        const open = if (snap.state == .upstream) "upstream" else @tagName(snap.state);
        addf(r, .pass, name, "template height {d}  subsidy {d}  port {d}  {s}. miners can be given a job", .{ snap.height, snap.subsidy, snap.port, open });
    }
    if (!any) add(r, .warn, "live.slots", "no chain source is attached in this process. save a module or set THIMBLE_RPC / THIMBLE_UPSTREAM and restart");
}

fn isIp4(host: []const u8) bool {
    if (host.len == 0 or host.len > 15) return false;
    var dots: u8 = 0;
    var group: u8 = 0;
    for (host) |c| {
        if (c == '.') {
            if (group == 0) return false;
            dots += 1;
            group = 0;
        } else if (c < '0' or c > '9') return false else group += 1;
    }
    return dots == 3 and group > 0;
}

fn hostPort(text: []const u8, host_out: []u8, port_out: *u16) ?[]const u8 {
    var s = text;
    if (std.mem.indexOf(u8, s, "://")) |i| s = s[i + 3 ..];
    if (std.mem.indexOfScalar(u8, s, '@')) |at| s = s[at + 1 ..];
    if (std.mem.indexOfScalar(u8, s, '/')) |sl| s = s[0..sl];
    const colon = std.mem.lastIndexOfScalar(u8, s, ':') orelse return null;
    if (colon == 0) return null;
    const n = @min(s[0..colon].len, host_out.len);
    @memcpy(host_out[0..n], s[0..colon]);
    port_out.* = std.fmt.parseInt(u16, s[colon + 1 ..], 10) catch return null;
    return host_out[0..n];
}

const Open = union(enum) { up: std.Io.net.Stream, down, skipped };

fn dial(host: []const u8, port: u16, why: []u8) Open {
    if (!isIp4(host)) {
        _ = put(why, "not an IPv4 address. this build does not resolve names");
        return .down;
    }
    if (!std.mem.eql(u8, host, "127.0.0.1")) {
        _ = put(why, "not dialed. only 127.0.0.1 is probed, so a dead remote host cannot stall this check");
        return .skipped;
    }
    const addr = std.Io.net.IpAddress.parseIp4(host, port) catch {
        _ = put(why, "address did not parse");
        return .down;
    };
    const stream = addr.connect(compat.io, .{ .mode = .stream, .protocol = .tcp, .timeout = .none }) catch |err| {
        _ = put(why, @errorName(err));
        return .down;
    };
    return .{ .up = stream };
}

fn writeAll(stream: std.Io.net.Stream, data: []const u8) !void {
    var buf: [700]u8 = undefined;
    var w = stream.writer(compat.io, &buf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

fn readSome(stream: std.Io.net.Stream, buf: []u8) ?[]u8 {
    const limit: std.Io.Timeout = .{ .duration = .{ .raw = .{ .nanoseconds = 1_500_000_000 }, .clock = .real } };
    const msg = stream.socket.receiveTimeout(compat.io, buf, limit) catch return null;
    if (msg.data.len == 0) return null;
    return msg.data;
}

fn quote(text: []const u8, out: []u8) []const u8 {
    var n: usize = 0;
    for (text) |c| {
        if (n + 1 >= out.len) break;
        if (c == '\r' or c == '\n') continue;
        out[n] = c;
        n += 1;
        if (n >= 70) break;
    }
    return out[0..n];
}

fn probeFeed(r: *Report, label: []const u8, text: []const u8) void {
    var host_buf: [80]u8 = undefined;
    var port: u16 = 0;
    const host = hostPort(text, &host_buf, &port) orelse {
        add(r, .fail, label, "could not read a host and port from the chain source");
        return;
    };
    var why: [120]u8 = @splat(0);
    switch (dial(host, port, &why)) {
        .skipped => {
            addf(r, .warn, label, "{s}:{d} {s}", .{ host, port, std.mem.sliceTo(&why, 0) });
            return;
        },
        .down => {
            addf(r, .fail, label, "cannot dial {s}:{d} ({s})", .{ host, port, std.mem.sliceTo(&why, 0) });
            return;
        },
        .up => |stream| {
            defer stream.close(compat.io);
            if (std.mem.startsWith(u8, text, "http://")) {
                askNode(r, label, text, host, port, stream);
            } else askStratum(r, label, host, port, stream);
        },
    }
}
fn askNode(r: *Report, label: []const u8, text: []const u8, host: []const u8, port: u16, stream: std.Io.net.Stream) void {
    const at = std.mem.indexOfScalar(u8, text, '@') orelse {
        add(r, .fail, label, "rpc URL has no user:pass@");
        return;
    };
    const scheme = std.mem.indexOf(u8, text, "://") orelse 0;
    const auth = text[scheme + 3 .. at];
    var auth_buf: [180]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&auth_buf, auth);
    const body = "{\"jsonrpc\":\"1.0\",\"id\":\"c\",\"method\":\"getblockchaininfo\",\"params\":[]}";
    var req: [520]u8 = undefined;
    const req_s = std.fmt.bufPrint(&req, "POST / HTTP/1.1\r\nHost: {s}:{d}\r\nAuthorization: Basic {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ host, port, b64, body.len, body }) catch {
        add(r, .fail, label, "rpc request did not fit");
        return;
    };
    writeAll(stream, req_s) catch {
        add(r, .fail, label, "rpc port accepted the connection and then refused the request");
        return;
    };
    var buf: [1800]u8 = undefined;
    const got = readSome(stream, &buf) orelse {
        addf(r, .warn, label, "rpc {s}:{d} is open but getblockchaininfo did not answer in 1.5s", .{ host, port });
        return;
    };
    if (std.mem.indexOf(u8, got, "\"blocks\":")) |_| {
        const height = jsonNum(got, "blocks") orelse 0;
        if (std.mem.indexOf(u8, got, "\"initialblockdownload\":true") != null) {
            addf(r, .warn, label, "node answered. height {d}. still downloading. the pool port stays closed until a template exists. pruned is enough", .{height});
        } else addf(r, .pass, label, "node answered getblockchaininfo. height {d}. not in initial download", .{height});
    } else {
        var snip: [80]u8 = undefined;
        addf(r, .fail, label, "node answered but not with a chain. {s}", .{quote(got, &snip)});
    }
}

fn askStratum(r: *Report, label: []const u8, host: []const u8, port: u16, stream: std.Io.net.Stream) void {
    const hello = "{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"thimble-check\"]}\n";
    writeAll(stream, hello) catch {
        add(r, .fail, label, "upstream accepted tcp and then refused the subscribe");
        return;
    };
    var buf: [900]u8 = undefined;
    const got = readSome(stream, &buf) orelse {
        addf(r, .warn, label, "upstream {s}:{d} is open but did not speak stratum within 1.5s", .{ host, port });
        return;
    };
    var snip: [80]u8 = undefined;
    if (std.mem.indexOf(u8, got, "\"result\"") == null and std.mem.indexOf(u8, got, "mining.notify") == null) {
        addf(r, .fail, label, "upstream is not stratum. {s}", .{quote(got, &snip)});
    } else if (std.mem.indexOf(u8, got, "no template") != null or std.mem.indexOf(u8, got, "no job") != null) {
        addf(r, .warn, label, "upstream speaks stratum and has no job yet. {s}", .{quote(got, &snip)});
    } else addf(r, .pass, label, "upstream {s}:{d} speaks stratum", .{ host, port });
}

fn jsonNum(text: []const u8, key: []const u8) ?u64 {
    var pat: [40]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "\"{s}\":", .{key}) catch return null;
    const at = std.mem.indexOf(u8, text, p) orelse return null;
    var i = at + p.len;
    while (i < text.len and text[i] == ' ') i += 1;
    var n: u64 = 0;
    var any = false;
    while (i < text.len and text[i] >= '0' and text[i] <= '9') : (i += 1) {
        any = true;
        n = n * 10 + (text[i] - '0');
    }
    return if (any) n else null;
}

fn already(seen: [][]const u8, text: []const u8) bool {
    for (seen) |s| if (std.mem.eql(u8, s, text)) return true;
    return false;
}

fn checkProbes(alloc: std.mem.Allocator, r: *Report) void {
    var seen_buf: [12][180]u8 = undefined;
    var seen: [12][]const u8 = undefined;
    var sn: usize = 0;
    for (&chain.slots) |*s| {
        if (!s.used or sn >= seen.len) continue;
        const snap = takeSnap(s);
        const text = if (snap.rpc_len > 8) snap.rpc[0..snap.rpc_len] else if (snap.upstream_len > 3) snap.upstream[0..snap.upstream_len] else continue;
        const n = put(&seen_buf[sn], text);
        seen[sn] = seen_buf[sn][0..n];
        sn += 1;
        var label: [40]u8 = undefined;
        const who = if (snap.name_len > 0) snap.name[0..snap.name_len] else "source";
        const name = std.fmt.bufPrint(&label, "dial.{s}", .{who}) catch "dial";
        probeFeed(r, name, text);
    }
    const raw = compat.fs.cwd().readFileAlloc(alloc, "pools.cfg", 1 << 16) catch return;
    defer alloc.free(raw);
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (line.len < 2 or line[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, line, '\t');
        const name = parts.next() orelse continue;
        _ = parts.next();
        _ = parts.next();
        const on = std.mem.eql(u8, parts.next() orelse "0", "1");
        _ = parts.next();
        _ = parts.next();
        const source = parts.next() orelse continue;
        if (!on or source.len < 3 or sn >= seen.len) continue;
        if (std.mem.startsWith(u8, source, "https://")) continue;
        if (already(seen[0..sn], source)) continue;
        const n = put(&seen_buf[sn], source);
        seen[sn] = seen_buf[sn][0..n];
        sn += 1;
        var label: [40]u8 = undefined;
        const tag = std.fmt.bufPrint(&label, "dial.{s}", .{name}) catch "dial";
        probeFeed(r, tag, source);
    }
}

fn checkListen(r: *Report, port: u16, label: []const u8, ready: bool, expect: bool) void {
    var why: [80]u8 = @splat(0);
    const opened = dial("127.0.0.1", port, &why);
    const open = opened == .up;
    if (opened == .up) opened.up.close(compat.io);
    if (!expect) return;
    if (ready and open) {
        addf(r, .pass, label, "port {d} is accepting miners", .{port});
    } else if (ready and !open) {
        addf(r, .fail, label, "a template is ready but port {d} is not listening ({s})", .{ port, std.mem.sliceTo(&why, 0) });
    } else if (!ready and open) {
        addf(r, .warn, label, "port {d} is open with no template. subscribe returns 'pool has no template yet'", .{port});
    } else addf(r, .pass, label, "port {d} is closed until a template. that is the rule", .{port});
}

fn checkPorts(r: *Report, opts: Opts) void {
    var why: [80]u8 = @splat(0);
    const sign = dial("127.0.0.1", 8080, &why);
    const sign_open = sign == .up;
    if (sign == .up) sign.up.close(compat.io);
    if (opts.expect_signon and !sign_open) {
        addf(r, .fail, "port.signon", "8080 is not accepting ({s}). members cannot sign on", .{std.mem.sliceTo(&why, 0)});
    } else if (opts.expect_signon) {
        add(r, .pass, "port.signon", "sign-on is accepting on 8080");
    } else if (!sign_open) {
        add(r, .pass, "port.signon", "sign-on is not started. this check is not the host");
    } else add(r, .pass, "port.signon", "something is already on 8080");

    if (!opts.expect_listen) return;
    var seen: [8]u16 = undefined;
    var sn: usize = 0;
    for (modules.mods[0..modules.count]) |m| {
        if (!m.on or sn >= seen.len) continue;
        var dup = false;
        for (seen[0..sn]) |p| {
            if (p == m.port) dup = true;
        }
        if (dup) continue;
        seen[sn] = m.port;
        sn += 1;
        const slot = chain.find(m.port);
        const ready = if (slot) |s| blk: {
            s.lock.lock();
            defer s.lock.unlock();
            break :blk s.job.ready;
        } else false;
        var label: [40]u8 = undefined;
        const name = std.fmt.bufPrint(&label, "port.{d}", .{m.port}) catch "port";
        checkListen(r, m.port, name, ready, true);
    }
    if (sn == 0) {
        for (&chain.slots) |*s| {
            if (!s.used or sn >= seen.len) continue;
            const snap = takeSnap(s);
            var label: [40]u8 = undefined;
            const name = std.fmt.bufPrint(&label, "port.{d}", .{snap.port}) catch "port";
            checkListen(r, snap.port, name, snap.ready, true);
            sn += 1;
        }
    }
}

pub fn run(alloc: std.mem.Allocator, opts: Opts) Report {
    var report = Report{};
    checkMath(alloc, &report);
    if (opts.files) checkFiles(&report);
    if (opts.config) checkConfig(alloc, &report);
    if (opts.live) checkLive(&report);
    if (opts.probe) checkProbes(alloc, &report);
    if (opts.expect_signon or opts.expect_listen or opts.probe) checkPorts(&report, opts);
    remember(&report);
    return report;
}

test "share math and the party split are what the pool pays" {
    var report = Report{};
    checkMath(std.testing.allocator, &report);
    for (report.items[0..report.n]) |f| {
        if (f.grade == .fail) std.debug.print("FAIL {s} {s}\n", .{ f.name[0..f.name_len], f.detail[0..f.detail_len] });
    }
    try std.testing.expectEqual(@as(u16, 0), report.fail_n);
}
