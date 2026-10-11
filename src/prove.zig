const std = @import("std");
const compat = @import("compat.zig");
const chain = @import("chain.zig");
const work = @import("work.zig");
const tls = @import("tls.zig");

pub fn main(init: std.process.Init) !void {
    compat.bind(init);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();
    const mode = args.next() orelse "btc";
    if (std.mem.eql(u8, mode, "tls")) return tlsEcho();
    const address = args.next() orelse return error.MissingAddress;
    if (std.mem.eql(u8, mode, "btc")) {
        try prove("sha256d", 18444, "http://thimble:thimble@127.0.0.1:18443", address);
    } else if (std.mem.eql(u8, mode, "ltc")) {
        try prove("scrypt", 19444, "http://thimble:thimble@127.0.0.1:19443", address);
    } else if (std.mem.eql(u8, mode, "aux")) {
        const doge = args.next() orelse address;
        try proveAux(address, doge);
    } else return error.UnknownMode;
}

fn prove(algo: []const u8, port: u16, url: []const u8, address: []const u8) !void {
    chain.setFeed(port, algo, url);
    chain.setWallet(port, address);
    var n: usize = 0;
    while (n < 12) : (n += 1) {
        chain.refresh(port);
        if (chain.ready(port)) break;
        compat.time.sleep(500 * std.time.ns_per_ms);
    }
    if (!chain.ready(port)) {
        var line: [500]u8 = undefined;
        std.debug.print("no template\n{s}\n", .{chain.statusLine(&line)});
        return error.NoTemplate;
    }
    if (!grind(port, algo)) {
        std.debug.print("submitblock refused: {s}\n", .{chain.submitText()});
        return error.SubmitFailed;
    }
    std.debug.print("submitblock accepted {s} {s}\n", .{ algo, chain.submitText() });
}

fn grind(port: u16, algo: []const u8) bool {
    const job = chain.snapshot(port);
    var nonce: u32 = 0;
    var shown = false;
    while (nonce < 20000) : (nonce += 1) {
        var nh: [8]u8 = undefined;
        const ns = std.fmt.bufPrint(&nh, "{x:0>8}", .{nonce}) catch continue;
        const checked = work.check(std.heap.page_allocator, algo, job.version[0..8], job.prevhash[0..64], job.coinb1[0..job.coinb1_len], job.en1[0..job.en1_len], "00000000", job.coinb2[0..job.coinb2_len], job.branch[0..job.branch_n], job.ntime[0..8], job.nbits[0..8], ns, 1, job.ready);
        if (!shown) {
            shown = true;
            std.debug.print("first verdict {s} height {d}\n", .{ @tagName(checked.verdict), job.height });
        }
        if (checked.verdict != .block and checked.verdict != .share) continue;
        if (checked.verdict != .block) continue;
        var coin: [1400]u8 = undefined;
        const cb = work.assemble(job.coinb1[0..job.coinb1_len], job.en1[0..job.en1_len], "00000000", job.coinb2[0..job.coinb2_len], &coin) orelse return false;
        var show: [180]u8 = undefined;
        const hx = work.hexEncode(&show, cb[0..@min(cb.len, 80)]);
        std.debug.print("coinbase {s}\n", .{hx});
        return chain.acceptBlock(port, checked.header, cb);
    }
    std.debug.print("no nonce met the network target\n", .{});
    return false;
}

fn proveAux(address: []const u8, doge_address: []const u8) !void {
    chain.setFeed(19444, "scrypt", "http://thimble:thimble@127.0.0.1:19443");
    chain.setWallet(19444, address);
    chain.setMerge(19444, "Dogecoin");
    const doge = chain.forPort(19332);
    doge.rpc_len = copyUrl(doge, "http://thimble:thimble@127.0.0.1:19332");
    doge.name_len = putName(doge, "Dogecoin");
    doge.wallet_len = putWallet(doge, doge_address);
    var n: usize = 0;
    while (n < 12) : (n += 1) {
        chain.refresh(19444);
        if (chain.ready(19444)) break;
        compat.time.sleep(500 * std.time.ns_per_ms);
    }
    if (!chain.ready(19444)) return error.NoTemplate;
    std.debug.print("aux note {s}\n", .{chain.submitText()});
    const job = chain.snapshot(19444);
    var nonce: u32 = 0;
    while (nonce < 20000) : (nonce += 1) {
        var nh: [8]u8 = undefined;
        const ns = std.fmt.bufPrint(&nh, "{x:0>8}", .{nonce}) catch continue;
        const checked = work.check(std.heap.page_allocator, "scrypt", job.version[0..8], job.prevhash[0..64], job.coinb1[0..job.coinb1_len], job.en1[0..job.en1_len], "00000000", job.coinb2[0..job.coinb2_len], job.branch[0..job.branch_n], job.ntime[0..8], job.nbits[0..8], ns, 1, true);
        if (checked.verdict != .block) continue;
        var coin: [1400]u8 = undefined;
        const cb = work.assemble(job.coinb1[0..job.coinb1_len], job.en1[0..job.en1_len], "00000000", job.coinb2[0..job.coinb2_len], &coin) orelse return error.BadCoinbase;
        if (!chain.acceptBlock(19444, checked.header, cb)) {
            std.debug.print("parent submitblock refused: {s}\n", .{chain.submitText()});
            return error.SubmitFailed;
        }
        if (!chain.acceptAux(19444, checked.header, cb, job.branch[0..job.branch_n])) {
            std.debug.print("submitauxblock refused: {s}\n", .{chain.submitText()});
            return error.AuxFailed;
        }
        std.debug.print("submitauxblock accepted {s}\n", .{chain.submitText()});
        return;
    }
    return error.NoNonce;
}

fn copyUrl(s: *chain.Source, url: []const u8) usize {
    const n = @min(url.len, s.rpc.len);
    @memcpy(s.rpc[0..n], url[0..n]);
    return n;
}

fn putName(s: *chain.Source, name: []const u8) usize {
    const n = @min(name.len, s.name.len);
    @memcpy(s.name[0..n], name[0..n]);
    return n;
}

fn tlsEcho() !void {
    const addr = try compat.net.Address.parseIp4("127.0.0.1", 14433);
    var server = try addr.listen(.{});
    std.debug.print("tls listening 14433\n", .{});
    const conn = try server.accept();
    defer conn.stream.close();
    var session = tls.accept(conn.stream) catch {
        std.debug.print("handshake failed: {s}\n", .{tls.reasonText()});
        return error.Tls;
    };
    var buf: [80]u8 = undefined;
    const n = session.read(&buf) catch {
        std.debug.print("read failed: {s}\n", .{tls.reasonText()});
        return error.Tls;
    };
    std.debug.print("got {s}\n", .{buf[0..n]});
    session.writeAll("ok\n") catch return error.Tls;
}

fn putWallet(s: *chain.Source, name: []const u8) usize {
    const n = @min(name.len, s.wallet.len);
    @memcpy(s.wallet[0..n], name[0..n]);
    return n;
}
