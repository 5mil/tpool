const std = @import("std");

pub const Verdict = enum { share, block, stale, bad, low, algo, no_job };

pub const Checked = struct {
    verdict: Verdict,
    hash: [32]u8 = @splat(0),
    header: [80]u8 = @splat(0),
};

pub fn checkedAlgo(name: []const u8) ?enum { sha256d, scrypt } {
    if (std.mem.eql(u8, name, "sha256d")) return .sha256d;
    if (std.mem.eql(u8, name, "scrypt")) return .scrypt;
    return null;
}

pub fn quotes(line: []const u8, out: [][]const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len and n < out.len) : (i += 1) {
        if (line[i] != '"') continue;
        const start = i + 1;
        var j = start;
        while (j < line.len and line[j] != '"') j += 1;
        if (j >= line.len) break;
        out[n] = line[start..j];
        n += 1;
        i = j;
    }
    return n;
}

pub fn hexDecode(dst: []u8, hex: []const u8) ?[]u8 {
    if (hex.len % 2 != 0 or hex.len / 2 > dst.len) return null;
    var n: usize = 0;
    while (n < hex.len / 2) : (n += 1) {
        const hi = hexVal(hex[n * 2]) orelse return null;
        const lo = hexVal(hex[n * 2 + 1]) orelse return null;
        dst[n] = (hi << 4) | lo;
    }
    return dst[0..n];
}

fn hexVal(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

pub fn hexEncode(dst: []u8, raw: []const u8) []u8 {
    const hexd = "0123456789abcdef";
    const n = @min(dst.len / 2, raw.len);
    for (raw[0..n], 0..) |b, i| {
        dst[i * 2] = hexd[b >> 4];
        dst[i * 2 + 1] = hexd[b & 0xf];
    }
    return dst[0 .. n * 2];
}

pub fn sha256d(data: []const u8) [32]u8 {
    var first: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &first, .{});
    var second: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &second, .{});
    return second;
}

pub fn scrypt1024(alloc: std.mem.Allocator, data: []const u8) ![32]u8 {
    var out: [32]u8 = undefined;
    try std.crypto.pwhash.scrypt.kdf(alloc, &out, data, data, .{ .ln = 10, .r = 1, .p = 1 });
    return out;
}

pub fn subsidy(algo: []const u8, height: u32) u64 {
    if (std.mem.eql(u8, algo, "sha256d")) {
        const era: u6 = @intCast(@min(height / 210_000, 32));
        return @as(u64, 5_000_000_000) >> era;
    }
    if (std.mem.eql(u8, algo, "scrypt")) {
        const era: u6 = @intCast(@min(height / 840_000, 32));
        return @as(u64, 5_000_000_000) >> era;
    }
    return 0;
}

pub fn targetFromBits(bits_hex: []const u8) ?[32]u8 {
    const nbits = parseHexU32(bits_hex) orelse return null;
    var target: [32]u8 = @splat(0);
    const exp: usize = nbits >> 24;
    const mant = nbits & 0x007fffff;
    if ((nbits & 0x00800000) != 0) return null;
    if (mant == 0 or exp == 0 or exp > 32) return target;
    if (exp <= 3) {
        const shifted = mant >> @intCast(8 * (3 - exp));
        writeLeU32(target[0..4], shifted);
    } else {
        const at = exp - 3;
        if (at >= 32) return target;
        var tmp: [4]u8 = undefined;
        writeLeU32(&tmp, mant);
        const n = @min(@as(usize, 4), 32 - at);
        @memcpy(target[at .. at + n], tmp[0..n]);
    }
    return target;
}

pub fn diff1() [32]u8 {
    var t: [32]u8 = @splat(0);
    t[26] = 0xff;
    t[27] = 0xff;
    return t;
}

pub fn divide(target: [32]u8, by: u32) [32]u8 {
    if (by <= 1) return target;
    var out: [32]u8 = @splat(0);
    var rem: u64 = 0;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        rem = (rem << 8) | target[i];
        out[i] = @truncate(rem / by);
        rem %= by;
    }
    return out;
}

pub fn meets(hash: [32]u8, target: [32]u8) bool {
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        if (hash[i] < target[i]) return true;
        if (hash[i] > target[i]) return false;
    }
    return true;
}

pub fn putBeHex(dst: []u8, hex: []const u8) ?void {
    if (dst.len < 4) return null;
    const v = parseHexU32(hex) orelse return null;
    writeLeU32(dst[0..4], v);
}

fn parseHexU32(hex: []const u8) ?u32 {
    if (hex.len == 0 or hex.len > 8) return null;
    var n: u32 = 0;
    for (hex) |c| {
        const v = hexVal(c) orelse return null;
        n = (n << 4) | v;
    }
    return n;
}

fn writeLeU32(dst: []u8, v: u32) void {
    dst[0] = @truncate(v);
    dst[1] = @truncate(v >> 8);
    dst[2] = @truncate(v >> 16);
    dst[3] = @truncate(v >> 24);
}

pub fn reverseGroups(dst: []u8, hex: []const u8) void {
    const n = @min(dst.len, hex.len);
    const groups = n / 8;
    var g: usize = 0;
    while (g < groups) : (g += 1) {
        const from = (groups - 1 - g) * 8;
        @memcpy(dst[g * 8 .. g * 8 + 8], hex[from .. from + 8]);
    }
}

pub fn stratumPrev(dst: []u8, hex: []const u8) ?void {
    var raw: [32]u8 = undefined;
    const got = hexDecode(&raw, hex) orelse return null;
    if (got.len != 32 or dst.len < 32) return null;
    var i: usize = 0;
    while (i < 32) : (i += 4) {
        dst[i] = raw[i + 3];
        dst[i + 1] = raw[i + 2];
        dst[i + 2] = raw[i + 1];
        dst[i + 3] = raw[i];
    }
}

pub fn merkleWithBranch(coinbase: []const u8, branch: []const [32]u8) [32]u8 {
    var root = sha256d(coinbase);
    for (branch) |b| {
        var cat: [64]u8 = undefined;
        @memcpy(cat[0..32], &root);
        @memcpy(cat[32..64], &b);
        root = sha256d(&cat);
    }
    return root;
}

pub fn coinbaseBranch(coin_hash: [32]u8, txids: []const [32]u8, out: [][32]u8) usize {
    var level: [8192][32]u8 = undefined;
    var n: usize = 1 + txids.len;
    if (n > level.len) n = level.len;
    level[0] = coin_hash;
    const leaves = @min(txids.len, n - 1);
    for (txids[0..leaves], 0..) |id, i| level[i + 1] = id;
    var written: usize = 0;
    while (n > 1 and written < out.len) {
        if (n % 2 == 1) {
            if (n >= level.len) break;
            level[n] = level[n - 1];
            n += 1;
        }
        out[written] = level[1];
        written += 1;
        var w: usize = 0;
        var i: usize = 0;
        while (i + 1 < n) : (i += 2) {
            var cat: [64]u8 = undefined;
            @memcpy(cat[0..32], &level[i]);
            @memcpy(cat[32..64], &level[i + 1]);
            level[w] = sha256d(&cat);
            w += 1;
        }
        n = w;
    }
    return written;
}

pub fn header(version_hex: []const u8, prev_hex: []const u8, root: [32]u8, ntime_hex: []const u8, nbits_hex: []const u8, nonce_hex: []const u8) ?[80]u8 {
    var out: [80]u8 = @splat(0);
    putBeHex(out[0..4], version_hex) orelse return null;
    stratumPrev(out[4..36], prev_hex) orelse return null;
    @memcpy(out[36..68], &root);
    putBeHex(out[68..72], ntime_hex) orelse return null;
    putBeHex(out[72..76], nbits_hex) orelse return null;
    putBeHex(out[76..80], nonce_hex) orelse return null;
    return out;
}

pub fn confirms(tip: u32, height: u32) u32 {
    if (height == 0 or tip < height) return 0;
    return tip - height + 1;
}

pub fn matured(tip: u32, height: u32) bool {
    return confirms(tip, height) >= 100;
}

pub fn hashrate(diff_sum: u64, seconds: i64) u64 {
    if (seconds <= 0 or diff_sum == 0) return 0;
    const num: u128 = @as(u128, diff_sum) << 32;
    return @intCast(num / @as(u128, @intCast(seconds)));
}

pub const Built = struct {
    raw: [900]u8 = undefined,
    raw_len: usize = 0,
    coinb1: [1600]u8 = undefined,
    coinb1_len: usize = 0,
    coinb2: [1600]u8 = undefined,
    coinb2_len: usize = 0,
    split: usize = 0,
};

pub fn outputScript(address: []const u8, dst: []u8) ?usize {
    if (dst.len < 40) return null;
    if (bech32Shape(address)) return bech32Script(address, dst);
    var raw: [40]u8 = undefined;
    const n = base58Decode(&raw, address) orelse return null;
    if (n != 25) return null;
    var sum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(raw[0 .. n - 4], &sum, .{});
    var sum2: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&sum, &sum2, .{});
    if (!std.mem.eql(u8, raw[n - 4 .. n], sum2[0..4])) return null;
    const version = raw[0];
    const hash = raw[1..21];
    if (version == 0x05 or version == 0xc4 or version == 0x32 or version == 0x16 or version == 0x3a) {
        dst[0] = 0xa9;
        dst[1] = 0x14;
        @memcpy(dst[2..22], hash);
        dst[22] = 0x87;
        return 23;
    }
    dst[0] = 0x76;
    dst[1] = 0xa9;
    dst[2] = 0x14;
    @memcpy(dst[3..23], hash);
    dst[23] = 0x88;
    dst[24] = 0xac;
    return 25;
}

fn bech32Shape(address: []const u8) bool {
    const sep = std.mem.lastIndexOfScalar(u8, address, '1') orelse return false;
    if (sep == 0 or address.len < sep + 7) return false;
    const data = address[sep + 1 ..];
    for (data) |c| if (bech32Val(c) == null) return false;
    return true;
}

fn bech32Val(c: u8) ?u8 {
    const alpha = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    if (c >= 'A' and c <= 'Z') return bech32Val(c + 32);
    const at = std.mem.indexOfScalar(u8, alpha, c) orelse return null;
    return @intCast(at);
}

fn bech32Polymod(values: []const u8) u32 {
    const gen = [_]u32{ 0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3 };
    var chk: u32 = 1;
    for (values) |v| {
        const top = chk >> 25;
        chk = (chk & 0x1ffffff) << 5 ^ v;
        var i: u5 = 0;
        while (i < 5) : (i += 1) {
            if ((top >> i) & 1 == 1) chk ^= gen[i];
        }
    }
    return chk;
}

fn bech32Script(address: []const u8, dst: []u8) ?usize {
    const sep = std.mem.lastIndexOfScalar(u8, address, '1') orelse return null;
    var hrp_buf: [32]u8 = undefined;
    if (sep > hrp_buf.len) return null;
    for (address[0..sep], 0..) |c, i| {
        if (c >= 'A' and c <= 'Z') hrp_buf[i] = c + 32 else hrp_buf[i] = c;
    }
    const hrp = hrp_buf[0..sep];
    var data: [100]u8 = undefined;
    var dn: usize = 0;
    for (address[sep + 1 ..]) |c| {
        if (dn >= data.len) return null;
        data[dn] = bech32Val(c) orelse return null;
        dn += 1;
    }
    if (dn < 7) return null;
    var vals: [160]u8 = undefined;
    var vn: usize = 0;
    for (hrp) |c| {
        vals[vn] = c >> 5;
        vn += 1;
    }
    vals[vn] = 0;
    vn += 1;
    for (hrp) |c| {
        vals[vn] = c & 31;
        vn += 1;
    }
    if (vn + dn > vals.len) return null;
    @memcpy(vals[vn .. vn + dn], data[0..dn]);
    const pm = bech32Polymod(vals[0 .. vn + dn]);
    const version = data[0];
    if (version == 0 and pm != 1) return null;
    if (version != 0 and pm != 0x2bc830a3) return null;
    if (version > 16) return null;
    var prog: [40]u8 = undefined;
    const pn = convertBits(data[1 .. dn - 6], &prog) orelse return null;
    if (pn < 2 or pn > 40) return null;
    if (version == 0 and pn != 20 and pn != 32) return null;
    if (version == 1 and pn != 32) return null;
    dst[0] = if (version == 0) 0 else 0x50 + version;
    dst[1] = @intCast(pn);
    @memcpy(dst[2 .. 2 + pn], prog[0..pn]);
    return 2 + pn;
}

fn convertBits(data: []const u8, dst: []u8) ?usize {
    var acc: u32 = 0;
    var bits: u32 = 0;
    var n: usize = 0;
    for (data) |v| {
        if (v > 31) return null;
        acc = (acc << 5) | v;
        bits += 5;
        if (bits >= 8) {
            bits -= 8;
            if (n >= dst.len) return null;
            dst[n] = @intCast((acc >> @intCast(bits)) & 0xff);
            n += 1;
        }
    }
    if (bits >= 5) return null;
    return n;
}

pub fn buildCoinbase(height: u32, value: u64, address: []const u8, aux: ?[32]u8, witness: []const u8) ?Built {
    var pk: [80]u8 = undefined;
    const pn = outputScript(address, &pk) orelse return null;
    var wit: [90]u8 = undefined;
    var wn: usize = 0;
    if (witness.len > 0) {
        const got = hexDecode(&wit, witness) orelse return null;
        wn = got.len;
        if (wn > 80) return null;
    }
    var sig: [120]u8 = undefined;
    var sn: usize = pushHeight(height, &sig);
    const en_at = sn;
    @memset(sig[sn .. sn + 8], 0);
    sn += 8;
    if (aux) |root| {
        if (sn + 44 > sig.len) return null;
        sig[sn] = 0xfa;
        sig[sn + 1] = 0xbe;
        sig[sn + 2] = 'm';
        sig[sn + 3] = 'm';
        @memcpy(sig[sn + 4 .. sn + 36], &root);
        sig[sn + 36] = 1;
        @memset(sig[sn + 37 .. sn + 44], 0);
        sn += 44;
    }
    if (sn > 100) return null;
    var b: Built = .{};
    var o: usize = 0;
    const raw = &b.raw;
    @memcpy(raw[0..4], &[_]u8{ 1, 0, 0, 0 });
    o = 4;
    raw[o] = 1;
    o += 1;
    @memset(raw[o .. o + 32], 0);
    o += 32;
    @memcpy(raw[o .. o + 4], &[_]u8{ 0xff, 0xff, 0xff, 0xff });
    o += 4;
    raw[o] = @intCast(sn);
    o += 1;
    @memcpy(raw[o .. o + en_at], sig[0..en_at]);
    o += en_at;
    b.split = o;
    @memset(raw[o .. o + 8], 0);
    o += 8;
    const tail = sn - en_at - 8;
    if (tail > 0) {
        @memcpy(raw[o .. o + tail], sig[en_at + 8 .. sn]);
        o += tail;
    }
    @memcpy(raw[o .. o + 4], &[_]u8{ 0xff, 0xff, 0xff, 0xff });
    o += 4;
    raw[o] = if (wn > 0) 2 else 1;
    o += 1;
    writeLeU64(raw[o .. o + 8], value);
    o += 8;
    raw[o] = @intCast(pn);
    o += 1;
    @memcpy(raw[o .. o + pn], pk[0..pn]);
    o += pn;
    if (wn > 0) {
        writeLeU64(raw[o .. o + 8], 0);
        o += 8;
        raw[o] = @intCast(wn);
        o += 1;
        @memcpy(raw[o .. o + wn], wit[0..wn]);
        o += wn;
    }
    @memset(raw[o .. o + 4], 0);
    o += 4;
    if (o > raw.len) return null;
    b.raw_len = o;
    const h1 = hexEncode(&b.coinb1, raw[0..b.split]);
    b.coinb1_len = h1.len;
    const h2 = hexEncode(&b.coinb2, raw[b.split + 8 .. o]);
    b.coinb2_len = h2.len;
    return b;
}

pub fn sealWitness(tx: []const u8, dst: []u8) ?[]u8 {
    if (tx.len < 10 or dst.len < tx.len + 40) return null;
    @memcpy(dst[0..4], tx[0..4]);
    dst[4] = 0x00;
    dst[5] = 0x01;
    const mid = tx.len - 4;
    @memcpy(dst[6 .. 6 + mid - 4], tx[4 .. tx.len - 4]);
    var o: usize = 6 + mid - 4;
    dst[o] = 1;
    o += 1;
    dst[o] = 32;
    o += 1;
    @memset(dst[o .. o + 32], 0);
    o += 32;
    @memcpy(dst[o .. o + 4], tx[tx.len - 4 ..]);
    return dst[0 .. o + 4];
}

pub fn hasCommitment(tx: []const u8) bool {
    const magic = [_]u8{ 0xaa, 0x21, 0xa9, 0xed };
    return std.mem.indexOf(u8, tx, &magic) != null;
}

fn writeLeU64(dst: []u8, v: u64) void {
    var i: usize = 0;
    var x = v;
    while (i < 8) : (i += 1) {
        dst[i] = @truncate(x);
        x >>= 8;
    }
}

fn pushHeight(h: u32, out: []u8) usize {
    if (h == 0) {
        out[0] = 0x00;
        return 1;
    }
    if (h <= 16) {
        out[0] = 0x50 + @as(u8, @intCast(h));
        return 1;
    }
    var tmp: [5]u8 = @splat(0);
    std.mem.writeInt(u32, tmp[0..4], h, .little);
    var n: usize = 4;
    while (n > 1 and tmp[n - 1] == 0) n -= 1;
    if (tmp[n - 1] & 0x80 != 0) n += 1;
    out[0] = @intCast(n);
    @memcpy(out[1 .. 1 + n], tmp[0..n]);
    return 1 + n;
}

fn base58Decode(dst: []u8, text: []const u8) ?usize {
    const alpha = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    var num: [40]u8 = @splat(0);
    for (text) |c| {
        const v: u32 = @intCast(std.mem.indexOfScalar(u8, alpha, c) orelse return null);
        var carry: u32 = v;
        var i: usize = 0;
        while (i < num.len) : (i += 1) {
            carry += @as(u32, num[num.len - 1 - i]) * 58;
            num[num.len - 1 - i] = @truncate(carry);
            carry >>= 8;
        }
        if (carry != 0) return null;
    }
    var zeros: usize = 0;
    for (text) |c| {
        if (c != '1') break;
        zeros += 1;
    }
    var start: usize = 0;
    while (start < num.len and num[start] == 0) start += 1;
    if (zeros + (num.len - start) > dst.len) return null;
    @memset(dst[0..zeros], 0);
    @memcpy(dst[zeros .. zeros + (num.len - start)], num[start..]);
    return zeros + (num.len - start);
}

pub fn assemble(coinb1_hex: []const u8, en1_hex: []const u8, en2_hex: []const u8, coinb2_hex: []const u8, out: []u8) ?[]u8 {
    var n: usize = 0;
    const a = hexDecode(out[n..], coinb1_hex) orelse return null;
    n += a.len;
    const b = hexDecode(out[n..], en1_hex) orelse return null;
    n += b.len;
    const c = hexDecode(out[n..], en2_hex) orelse return null;
    n += c.len;
    const d = hexDecode(out[n..], coinb2_hex) orelse return null;
    n += d.len;
    return out[0..n];
}

pub fn check(alloc: std.mem.Allocator, algo: []const u8, version: []const u8, prev: []const u8, coinb1: []const u8, en1: []const u8, en2: []const u8, coinb2: []const u8, branch: []const [32]u8, ntime: []const u8, nbits: []const u8, nonce: []const u8, diff: u32, ready: bool) Checked {
    const kind = checkedAlgo(algo) orelse return .{ .verdict = .algo };
    if (!ready or prev.len < 64 or nbits.len < 8) return .{ .verdict = .no_job };
    var coin_buf: [900]u8 = undefined;
    const coin = assemble(coinb1, en1, en2, coinb2, &coin_buf) orelse return .{ .verdict = .bad };
    const root = merkleWithBranch(coin, branch);
    const head = header(version, prev, root, ntime, nbits, nonce) orelse return .{ .verdict = .bad };
    const hash = switch (kind) {
        .sha256d => sha256d(&head),
        .scrypt => scrypt1024(alloc, &head) catch return .{ .verdict = .bad },
    };
    const net = targetFromBits(nbits) orelse return .{ .verdict = .bad };
    const share_target = divide(diff1(), if (diff == 0) 1 else diff);
    if (meets(hash, net)) return .{ .verdict = .block, .hash = hash, .header = head };
    if (meets(hash, share_target)) return .{ .verdict = .share, .hash = hash, .header = head };
    return .{ .verdict = .low, .hash = hash, .header = head };
}

test "genesis header hashes to the bitcoin genesis block" {
    const hdr = "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c";
    var raw: [80]u8 = undefined;
    const n = hexDecode(&raw, hdr).?;
    const hash = sha256d(n);
    var show: [64]u8 = undefined;
    var rev: [32]u8 = undefined;
    for (0..32) |i| rev[i] = hash[31 - i];
    const hex = hexEncode(&show, &rev);
    try std.testing.expectEqualStrings("000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f", hex);
}

test "a share under the target passes and a zero hash is a block" {
    const easy: [32]u8 = @splat(0xff);
    const hard: [32]u8 = @splat(0);
    try std.testing.expect(meets(hard, easy));
    try std.testing.expect(!meets(easy, hard));
    const bits = targetFromBits("1d00ffff").?;
    try std.testing.expect(meets(hard, bits));
}

test "regtest compact bits are a real target, not zero" {
    const bits = targetFromBits("207fffff").?;
    try std.testing.expect(bits[31] == 0x7f);
    try std.testing.expect(bits[30] == 0xff);
    try std.testing.expect(meets(@splat(0), bits));
}

test "bc1 decodes to the BIP173 witness program" {
    var script: [40]u8 = undefined;
    const n = outputScript("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", &script).?;
    try std.testing.expectEqual(@as(usize, 22), n);
    try std.testing.expect(script[0] == 0 and script[1] == 20);
    var expect_h: [20]u8 = undefined;
    _ = hexDecode(&expect_h, "751e76e8199196d454941c45d1b3a323f1433bd6").?;
    try std.testing.expect(std.mem.eql(u8, script[2..22], &expect_h));
}

test "coinbase for a bc1 address carries a segwit witness" {
    const built = buildCoinbase(1, 5_000_000_000, "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", null, "6a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf9").?;
    var tx: [900]u8 = undefined;
    const coin = assemble(built.coinb1[0..built.coinb1_len], "00000000", "00000000", built.coinb2[0..built.coinb2_len], &tx).?;
    try std.testing.expect(hasCommitment(coin));
    var sealed: [900]u8 = undefined;
    const full = sealWitness(coin, &sealed).?;
    try std.testing.expect(full[4] == 0 and full[5] == 1);
    try std.testing.expect(full[full.len - 37] == 32);
    try std.testing.expect(full[full.len - 38] == 1);
}

test "a block is spendable only after 100 confirmations" {
    try std.testing.expect(!matured(100, 100));
    try std.testing.expectEqual(@as(u32, 99), confirms(198, 100));
    try std.testing.expect(matured(199, 100));
}
