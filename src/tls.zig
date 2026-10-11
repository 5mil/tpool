const compat = @import("compat.zig");
const std = @import("std");

const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Aes = std.crypto.aead.aes_gcm.Aes128Gcm;
const X25519 = std.crypto.dh.X25519;
const Ecdsa = std.crypto.sign.ecdsa.EcdsaP256Sha256;

pub var reason: [140]u8 = @splat(0);
pub var reason_len: usize = 0;

fn fail(text: []const u8) error{Tls} {
    const n = @min(text.len, reason.len);
    @memcpy(reason[0..n], text[0..n]);
    reason_len = n;
    return error.Tls;
}

pub fn reasonText() []const u8 {
    if (reason_len == 0) return "";
    return reason[0..reason_len];
}

const Identity = struct {
    key: Ecdsa.KeyPair,
    cert: [560]u8 = undefined,
    cert_len: usize = 0,
};

var identity: ?Identity = null;

fn ensureIdentity() error{Tls}!Identity {
    if (identity) |id| return id;
    var seed: [32]u8 = @splat(0x31);
    const t: u64 = @intCast(@max(compat.time.timestamp(), 1));
    std.mem.writeInt(u64, seed[0..8], t, .little);
    const key = Ecdsa.KeyPair.generateDeterministic(seed) catch return fail("certificate key");
    var id = Identity{ .key = key };
    id.cert_len = writeCert(&id.cert, key) catch return fail("certificate");
    identity = id;
    return id;
}

fn putLen(dst: []u8, n: usize) usize {
    if (n < 128) {
        dst[0] = @intCast(n);
        return 1;
    }
    if (n < 256) {
        dst[0] = 0x81;
        dst[1] = @intCast(n);
        return 2;
    }
    dst[0] = 0x82;
    std.mem.writeInt(u16, dst[1..3], @intCast(@min(n, 65535)), .big);
    return 3;
}

fn writeCert(dst: []u8, key: Ecdsa.KeyPair) !usize {
    var tbs: [400]u8 = undefined;
    const tbs_len = writeTbs(&tbs, key.public_key.toUncompressedSec1());
    var der: [72]u8 = undefined;
    const sig = key.sign(tbs[0..tbs_len], null) catch return error.Tls;
    const sig_bytes = sig.toDer(&der);
    var body: [500]u8 = undefined;
    var b: usize = 0;
    @memcpy(body[b .. b + tbs_len], tbs[0..tbs_len]);
    b += tbs_len;
    const alg = [_]u8{ 0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02 };
    @memcpy(body[b .. b + alg.len], &alg);
    b += alg.len;
    body[b] = 0x03;
    b += 1;
    b += putLen(body[b..], sig_bytes.len + 1);
    body[b] = 0x00;
    b += 1;
    @memcpy(body[b .. b + sig_bytes.len], sig_bytes);
    b += sig_bytes.len;
    if (dst.len < b + 4) return error.Tls;
    dst[0] = 0x30;
    const n = putLen(dst[1..], b);
    @memcpy(dst[1 + n .. 1 + n + b], body[0..b]);
    return 1 + n + b;
}

fn writeTbs(dst: []u8, public: [65]u8) usize {
    var body: [340]u8 = undefined;
    var b: usize = 0;
    const ver = [_]u8{ 0xa0, 0x03, 0x02, 0x01, 0x02 };
    @memcpy(body[b .. b + ver.len], &ver);
    b += ver.len;
    const serial = [_]u8{ 0x02, 0x08, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
    @memcpy(body[b .. b + serial.len], &serial);
    b += serial.len;
    const alg = [_]u8{ 0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02 };
    @memcpy(body[b .. b + alg.len], &alg);
    b += alg.len;
    b += putName(body[b..]);
    const when = [_]u8{ 0x30, 0x1e, 0x17, 0x0d, '2', '4', '0', '1', '0', '1', '0', '0', '0', '0', '0', '0', 'Z', 0x17, 0x0d, '3', '5', '0', '1', '0', '1', '0', '0', '0', '0', '0', '0', 'Z' };
    @memcpy(body[b .. b + when.len], &when);
    b += when.len;
    b += putName(body[b..]);
    b += putSpki(body[b..], public);
    dst[0] = 0x30;
    const n = putLen(dst[1..], b);
    @memcpy(dst[1 + n .. 1 + n + b], body[0..b]);
    return 1 + n + b;
}

fn putName(dst: []u8) usize {
    const cn = "thimble";
    var set_body: [24]u8 = undefined;
    var s: usize = 0;
    set_body[s] = 0x06;
    s += 1;
    set_body[s] = 0x03;
    s += 1;
    @memcpy(set_body[s .. s + 3], &[_]u8{ 0x55, 0x04, 0x03 });
    s += 3;
    set_body[s] = 0x13;
    s += 1;
    set_body[s] = @intCast(cn.len);
    s += 1;
    @memcpy(set_body[s .. s + cn.len], cn);
    s += cn.len;
    var seq: [28]u8 = undefined;
    seq[0] = 0x30;
    const sn = putLen(seq[1..], s);
    @memcpy(seq[1 + sn .. 1 + sn + s], set_body[0..s]);
    const seq_len = 1 + sn + s;
    var set: [32]u8 = undefined;
    set[0] = 0x31;
    const tn = putLen(set[1..], seq_len);
    @memcpy(set[1 + tn .. 1 + tn + seq_len], seq[0..seq_len]);
    const set_len = 1 + tn + seq_len;
    dst[0] = 0x30;
    const on = putLen(dst[1..], set_len);
    @memcpy(dst[1 + on .. 1 + on + set_len], set[0..set_len]);
    return 1 + on + set_len;
}

fn putSpki(dst: []u8, public: [65]u8) usize {
    const alg = [_]u8{ 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07 };
    var bit: [70]u8 = undefined;
    bit[0] = 0x03;
    bit[1] = 66;
    bit[2] = 0x00;
    @memcpy(bit[3..68], &public);
    var body: [96]u8 = undefined;
    @memcpy(body[0..alg.len], &alg);
    @memcpy(body[alg.len .. alg.len + 68], bit[0..68]);
    const bl = alg.len + 68;
    dst[0] = 0x30;
    const n = putLen(dst[1..], bl);
    @memcpy(dst[1 + n .. 1 + n + bl], body[0..bl]);
    return 1 + n + bl;
}

fn prf(secret: []const u8, label: []const u8, seed: []const u8, out: []u8) void {
    var label_seed: [96]u8 = undefined;
    @memcpy(label_seed[0..label.len], label);
    @memcpy(label_seed[label.len .. label.len + seed.len], seed);
    const ls = label_seed[0 .. label.len + seed.len];
    var a: [32]u8 = undefined;
    Hmac.create(&a, ls, secret);
    var filled: usize = 0;
    while (filled < out.len) {
        var msg: [140]u8 = undefined;
        @memcpy(msg[0..32], &a);
        @memcpy(msg[32 .. 32 + ls.len], ls);
        var block: [32]u8 = undefined;
        Hmac.create(&block, msg[0 .. 32 + ls.len], secret);
        const n = @min(out.len - filled, block.len);
        @memcpy(out[filled .. filled + n], block[0..n]);
        filled += n;
        Hmac.create(&a, &a, secret);
    }
}

const Acc = struct {
    buf: [20000]u8 = undefined,
    len: usize = 0,
};

fn fill(stream: compat.net.Stream, acc: *Acc, need: usize) !void {
    while (acc.len < need) {
        const n = stream.read(acc.buf[acc.len..]) catch return fail("peer closed");
        if (n == 0) return fail("peer closed");
        acc.len += n;
    }
}

fn readRec(stream: compat.net.Stream, acc: *Acc, payload: []u8) !struct { typ: u8, len: usize } {
    try fill(stream, acc, 5);
    const typ = acc.buf[0];
    const n: usize = std.mem.readInt(u16, acc.buf[3..5], .big);
    if (n > payload.len) return fail("record too large");
    try fill(stream, acc, 5 + n);
    @memcpy(payload[0..n], acc.buf[5 .. 5 + n]);
    const rest = acc.len - (5 + n);
    std.mem.copyForwards(u8, acc.buf[0..rest], acc.buf[5 + n .. acc.len]);
    acc.len = rest;
    return .{ .typ = typ, .len = n };
}

fn writeRec(stream: compat.net.Stream, typ: u8, payload: []const u8) !void {
    var head: [5]u8 = .{ typ, 0x03, 0x03, 0, 0 };
    std.mem.writeInt(u16, head[3..5], @intCast(payload.len), .big);
    stream.writeAll(&head) catch return fail("write");
    stream.writeAll(payload) catch return fail("write");
}

fn put24(dst: []u8, n: usize) void {
    dst[0] = @intCast((n >> 16) & 0xff);
    dst[1] = @intCast((n >> 8) & 0xff);
    dst[2] = @intCast(n & 0xff);
}

const Hello = struct {
    random: [32]u8 = @splat(0),
    sid: [32]u8 = @splat(0),
    sid_len: usize = 0,
    cipher: bool = false,
};

fn parseHello(msg: []const u8) !Hello {
    if (msg.len < 40 or msg[0] != 1) return fail("client hello");
    var i: usize = 4;
    if (i + 34 > msg.len) return fail("client hello");
    i += 2;
    var hello = Hello{};
    @memcpy(&hello.random, msg[i .. i + 32]);
    i += 32;
    const sid_len = msg[i];
    i += 1;
    if (i + sid_len + 2 > msg.len) return fail("client hello");
    hello.sid_len = @min(sid_len, hello.sid.len);
    @memcpy(hello.sid[0..hello.sid_len], msg[i .. i + hello.sid_len]);
    i += sid_len;
    const cs = std.mem.readInt(u16, msg[i .. i + 2][0..2], .big);
    i += 2;
    var c: usize = 0;
    while (c + 1 < cs and i + c + 1 < msg.len) : (c += 2) {
        if (msg[i + c] == 0xc0 and msg[i + c + 1] == 0x2b) hello.cipher = true;
    }
    return hello;
}

fn serverFlight(dst: []u8, hello: Hello, random: [32]u8, pubkey: [32]u8, id: Identity) !usize {
    var o: usize = 0;
    var sh: [80]u8 = undefined;
    var s: usize = 0;
    @memcpy(sh[s .. s + 2], &[_]u8{ 0x03, 0x03 });
    s += 2;
    @memcpy(sh[s .. s + 32], &random);
    s += 32;
    sh[s] = @intCast(hello.sid_len);
    s += 1;
    @memcpy(sh[s .. s + hello.sid_len], hello.sid[0..hello.sid_len]);
    s += hello.sid_len;
    @memcpy(sh[s .. s + 2], &[_]u8{ 0xc0, 0x2b });
    s += 2;
    sh[s] = 0;
    s += 1;
    @memcpy(sh[s .. s + 7], &[_]u8{ 0x00, 0x05, 0xff, 0x01, 0x00, 0x01, 0x00 });
    s += 7;
    dst[o] = 2;
    o += 1;
    put24(dst[o..], s);
    o += 3;
    @memcpy(dst[o .. o + s], sh[0..s]);
    o += s;
    var certs: [600]u8 = undefined;
    put24(certs[3..], id.cert_len);
    @memcpy(certs[6 .. 6 + id.cert_len], id.cert[0..id.cert_len]);
    const list = 3 + id.cert_len;
    put24(certs[0..], list);
    const cert_body = 3 + list;
    dst[o] = 11;
    o += 1;
    put24(dst[o..], cert_body);
    o += 3;
    @memcpy(dst[o .. o + cert_body], certs[0..cert_body]);
    o += cert_body;
    var params: [40]u8 = undefined;
    params[0] = 0x03;
    params[1] = 0x00;
    params[2] = 0x1d;
    params[3] = 32;
    @memcpy(params[4..36], &pubkey);
    var signed_in: [120]u8 = undefined;
    @memcpy(signed_in[0..32], &hello.random);
    @memcpy(signed_in[32..64], &random);
    @memcpy(signed_in[64..100], params[0..36]);
    var der: [72]u8 = undefined;
    const sig = id.key.sign(signed_in[0..100], null) catch return fail("sign");
    const sig_bytes = sig.toDer(&der);
    var kex: [160]u8 = undefined;
    @memcpy(kex[0..36], params[0..36]);
    kex[36] = 0x04;
    kex[37] = 0x03;
    std.mem.writeInt(u16, kex[38..40], @intCast(sig_bytes.len), .big);
    @memcpy(kex[40 .. 40 + sig_bytes.len], sig_bytes);
    const kex_len = 40 + sig_bytes.len;
    dst[o] = 12;
    o += 1;
    put24(dst[o..], kex_len);
    o += 3;
    @memcpy(dst[o .. o + kex_len], kex[0..kex_len]);
    o += kex_len;
    dst[o] = 14;
    o += 1;
    put24(dst[o..], 0);
    return o + 3;
}

fn clientPoint(msg: []const u8) ?[32]u8 {
    var i: usize = 0;
    while (i + 4 <= msg.len) {
        const typ = msg[i];
        const n: usize = (@as(usize, msg[i + 1]) << 16) | (@as(usize, msg[i + 2]) << 8) | msg[i + 3];
        i += 4;
        if (i + n > msg.len) return null;
        if (typ == 16 and n >= 33 and msg[i] == 32) {
            var out: [32]u8 = undefined;
            @memcpy(&out, msg[i + 1 .. i + 33]);
            return out;
        }
        i += n;
    }
    return null;
}

pub const Session = struct {
    stream: compat.net.Stream,
    key: [16]u8 = @splat(0),
    iv: [4]u8 = @splat(0),
    peer_key: [16]u8 = @splat(0),
    peer_iv: [4]u8 = @splat(0),
    seq: u64 = 0,
    peer_seq: u64 = 0,
    acc: Acc = .{},
    plain: [17000]u8 = undefined,
    plain_len: usize = 0,
    plain_pos: usize = 0,

    pub fn read(self: *Session, buf: []u8) !usize {
        if (self.plain_pos >= self.plain_len) try self.pullApp();
        const n = @min(buf.len, self.plain_len - self.plain_pos);
        if (n == 0) return 0;
        @memcpy(buf[0..n], self.plain[self.plain_pos .. self.plain_pos + n]);
        self.plain_pos += n;
        return n;
    }

    pub fn writeAll(self: *Session, data: []const u8) !void {
        try self.writeCrypt(0x17, data);
    }

    fn pullApp(self: *Session) !void {
        var payload: [18000]u8 = undefined;
        const rec = try readRec(self.stream, &self.acc, &payload);
        if (rec.typ == 0x15) return fail("peer alert");
        var out: [17000]u8 = undefined;
        const plain = try self.decrypt(&out, rec.typ, payload[0..rec.len]);
        self.plain_len = plain.len;
        self.plain_pos = 0;
        @memcpy(self.plain[0..plain.len], plain);
    }

    fn writeCrypt(self: *Session, typ: u8, data: []const u8) !void {
        var explicit: [8]u8 = undefined;
        std.mem.writeInt(u64, &explicit, self.seq, .big);
        var nonce: [12]u8 = undefined;
        @memcpy(nonce[0..4], &self.iv);
        @memcpy(nonce[4..12], &explicit);
        var ad: [13]u8 = undefined;
        std.mem.writeInt(u64, ad[0..8], self.seq, .big);
        ad[8] = typ;
        ad[9] = 0x03;
        ad[10] = 0x03;
        std.mem.writeInt(u16, ad[11..13], @intCast(data.len), .big);
        var cipher: [17000]u8 = undefined;
        if (data.len > cipher.len) return fail("record too large");
        var tag: [16]u8 = undefined;
        Aes.encrypt(cipher[0..data.len], &tag, data, &ad, nonce, self.key);
        var wire: [18000]u8 = undefined;
        @memcpy(wire[0..8], &explicit);
        @memcpy(wire[8 .. 8 + data.len], cipher[0..data.len]);
        @memcpy(wire[8 + data.len .. 8 + data.len + 16], &tag);
        try writeRec(self.stream, typ, wire[0 .. 8 + data.len + 16]);
        self.seq += 1;
    }

    fn decrypt(self: *Session, out: []u8, typ: u8, wire: []const u8) ![]u8 {
        if (wire.len < 24) return fail("short record");
        const data_len = wire.len - 24;
        if (data_len > out.len) return fail("record too large");
        var nonce: [12]u8 = undefined;
        @memcpy(nonce[0..4], &self.peer_iv);
        @memcpy(nonce[4..12], wire[0..8]);
        var ad: [13]u8 = undefined;
        std.mem.writeInt(u64, ad[0..8], self.peer_seq, .big);
        ad[8] = typ;
        ad[9] = 0x03;
        ad[10] = 0x03;
        std.mem.writeInt(u16, ad[11..13], @intCast(data_len), .big);
        var tag: [16]u8 = undefined;
        @memcpy(&tag, wire[wire.len - 16 ..]);
        Aes.decrypt(out[0..data_len], wire[8 .. 8 + data_len], tag, &ad, nonce, self.peer_key) catch return fail("bad record mac");
        self.peer_seq += 1;
        return out[0..data_len];
    }
};

fn mix() [32]u8 {
    var block: [16]u8 = undefined;
    const t: u64 = @intCast(@max(compat.time.timestamp(), 1));
    std.mem.writeInt(u64, block[0..8], t, .little);
    std.mem.writeInt(u64, block[8..16], t *% 0x9e3779b97f4a7c15 +% 1, .little);
    var out: [32]u8 = undefined;
    Sha256.hash(&block, &out, .{});
    return out;
}

pub fn accept(stream: compat.net.Stream) !Session {
    const id = try ensureIdentity();
    var acc = Acc{};
    var payload: [18000]u8 = undefined;
    const hello_rec = try readRec(stream, &acc, &payload);
    if (hello_rec.typ != 0x16) return fail("not a handshake");
    var transcript: [16000]u8 = undefined;
    if (hello_rec.len > transcript.len) return fail("hello too large");
    @memcpy(transcript[0..hello_rec.len], payload[0..hello_rec.len]);
    var tlen: usize = hello_rec.len;
    const hello = try parseHello(payload[0..hello_rec.len]);
    if (!hello.cipher) return fail("miner did not offer ECDHE-ECDSA-AES128-GCM");
    const server_random = mix();
    const eph = X25519.KeyPair.generateDeterministic(mix());
    var flight: [1400]u8 = undefined;
    const flight_len = try serverFlight(&flight, hello, server_random, eph.public_key, id);
    try writeRec(stream, 0x16, flight[0..flight_len]);
    if (tlen + flight_len > transcript.len) return fail("transcript");
    @memcpy(transcript[tlen .. tlen + flight_len], flight[0..flight_len]);
    tlen += flight_len;
    var session = Session{ .stream = stream, .acc = acc };
    var master: [48]u8 = undefined;
    var keyed = false;
    while (true) {
        const rec = try readRec(stream, &session.acc, &payload);
        if (rec.typ == 0x15) return fail("peer alert");
        if (rec.typ == 0x14) break;
        if (rec.typ != 0x16) return fail("expected the client key");
        const point = clientPoint(payload[0..rec.len]) orelse return fail("client key");
        const shared = X25519.scalarmult(eph.secret_key, point) catch return fail("shared secret");
        var seed: [64]u8 = undefined;
        @memcpy(seed[0..32], &hello.random);
        @memcpy(seed[32..64], &server_random);
        prf(&shared, "master secret", &seed, &master);
        var expansion: [40]u8 = undefined;
        var seed2: [64]u8 = undefined;
        @memcpy(seed2[0..32], &server_random);
        @memcpy(seed2[32..64], &hello.random);
        prf(&master, "key expansion", &seed2, &expansion);
        @memcpy(&session.peer_key, expansion[0..16]);
        @memcpy(&session.key, expansion[16..32]);
        @memcpy(&session.peer_iv, expansion[32..36]);
        @memcpy(&session.iv, expansion[36..40]);
        if (tlen + rec.len > transcript.len) return fail("transcript");
        @memcpy(transcript[tlen .. tlen + rec.len], payload[0..rec.len]);
        tlen += rec.len;
        keyed = true;
    }
    if (!keyed) return fail("no client key");
    const fin = try readRec(stream, &session.acc, &payload);
    if (fin.typ != 0x16) return fail("no client finished");
    var plain_buf: [80]u8 = undefined;
    const plain = try session.decrypt(&plain_buf, fin.typ, payload[0..fin.len]);
    var hash: [32]u8 = undefined;
    Sha256.hash(transcript[0..tlen], &hash, .{});
    var expect: [12]u8 = undefined;
    prf(&master, "client finished", &hash, &expect);
    if (plain.len != 16 or plain[0] != 0x14 or !std.mem.eql(u8, plain[4..16], &expect)) return fail("bad client finished");
    if (tlen + plain.len > transcript.len) return fail("transcript");
    @memcpy(transcript[tlen .. tlen + plain.len], plain);
    tlen += plain.len;
    Sha256.hash(transcript[0..tlen], &hash, .{});
    var mine: [12]u8 = undefined;
    prf(&master, "server finished", &hash, &mine);
    var done: [16]u8 = undefined;
    done[0] = 0x14;
    put24(done[1..], 12);
    @memcpy(done[4..16], &mine);
    try writeRec(stream, 0x14, &[_]u8{0x01});
    try session.writeCrypt(0x16, &done);
    return session;
}

fn serverPoint(msg: []const u8) ?struct { random: [32]u8, point: [32]u8 } {
    var i: usize = 0;
    var random: [32]u8 = @splat(0);
    var point: [32]u8 = @splat(0);
    var got_r = false;
    var got_p = false;
    while (i + 4 <= msg.len) {
        const typ = msg[i];
        const n: usize = (@as(usize, msg[i + 1]) << 16) | (@as(usize, msg[i + 2]) << 8) | msg[i + 3];
        i += 4;
        if (i + n > msg.len) return null;
        if (typ == 2 and n >= 34) {
            @memcpy(&random, msg[i + 2 .. i + 34]);
            got_r = true;
        }
        if (typ == 12 and n >= 36 and msg[i + 3] == 32) {
            @memcpy(&point, msg[i + 4 .. i + 36]);
            got_p = true;
        }
        i += n;
    }
    if (!got_r or !got_p) return null;
    return .{ .random = random, .point = point };
}

pub fn connect(stream: compat.net.Stream) !Session {
    const client_random = mix();
    var hello: [80]u8 = undefined;
    var h: usize = 0;
    hello[h] = 1;
    h += 1;
    put24(hello[h..], 0);
    h += 3;
    const body = h;
    @memcpy(hello[h .. h + 2], &[_]u8{ 0x03, 0x03 });
    h += 2;
    @memcpy(hello[h .. h + 32], &client_random);
    h += 32;
    hello[h] = 0;
    h += 1;
    @memcpy(hello[h .. h + 2], &[_]u8{ 0x00, 0x02 });
    h += 2;
    @memcpy(hello[h .. h + 2], &[_]u8{ 0xc0, 0x2b });
    h += 2;
    hello[h] = 1;
    h += 1;
    hello[h] = 0;
    h += 1;
    put24(hello[body - 3 ..], h - body);
    try writeRec(stream, 0x16, hello[0..h]);
    var acc = Acc{};
    var payload: [18000]u8 = undefined;
    const flight = try readRec(stream, &acc, &payload);
    if (flight.typ != 0x16) return fail("no server hello");
    const parsed = serverPoint(payload[0..flight.len]) orelse return fail("server key");
    var transcript: [16000]u8 = undefined;
    if (h + flight.len > transcript.len) return fail("transcript");
    @memcpy(transcript[0..h], hello[0..h]);
    @memcpy(transcript[h .. h + flight.len], payload[0..flight.len]);
    var tlen: usize = h + flight.len;
    const eph = X25519.KeyPair.generateDeterministic(mix());
    var kex: [40]u8 = undefined;
    kex[0] = 16;
    put24(kex[1..], 33);
    kex[4] = 32;
    @memcpy(kex[5..37], &eph.public_key);
    try writeRec(stream, 0x16, kex[0..37]);
    if (tlen + 37 > transcript.len) return fail("transcript");
    @memcpy(transcript[tlen .. tlen + 37], kex[0..37]);
    tlen += 37;
    const shared = X25519.scalarmult(eph.secret_key, parsed.point) catch return fail("shared secret");
    var seed: [64]u8 = undefined;
    @memcpy(seed[0..32], &client_random);
    @memcpy(seed[32..64], &parsed.random);
    var master: [48]u8 = undefined;
    prf(&shared, "master secret", &seed, &master);
    var expansion: [40]u8 = undefined;
    var seed2: [64]u8 = undefined;
    @memcpy(seed2[0..32], &parsed.random);
    @memcpy(seed2[32..64], &client_random);
    prf(&master, "key expansion", &seed2, &expansion);
    var session = Session{ .stream = stream, .acc = acc };
    @memcpy(&session.key, expansion[0..16]);
    @memcpy(&session.peer_key, expansion[16..32]);
    @memcpy(&session.iv, expansion[32..36]);
    @memcpy(&session.peer_iv, expansion[36..40]);
    try writeRec(stream, 0x14, &[_]u8{0x01});
    var hash: [32]u8 = undefined;
    Sha256.hash(transcript[0..tlen], &hash, .{});
    var verify: [12]u8 = undefined;
    prf(&master, "client finished", &hash, &verify);
    var done: [16]u8 = undefined;
    done[0] = 0x14;
    put24(done[1..], 12);
    @memcpy(done[4..16], &verify);
    try session.writeCrypt(0x16, &done);
    const ccs = try readRec(stream, &session.acc, &payload);
    if (ccs.typ != 0x14) return fail("no server ccs");
    const fin = try readRec(stream, &session.acc, &payload);
    if (fin.typ != 0x16) return fail("no server finished");
    var plain_buf: [80]u8 = undefined;
    const plain = try session.decrypt(&plain_buf, fin.typ, payload[0..fin.len]);
    if (tlen + 16 > transcript.len) return fail("transcript");
    @memcpy(transcript[tlen .. tlen + 16], &done);
    tlen += 16;
    Sha256.hash(transcript[0..tlen], &hash, .{});
    var expect: [12]u8 = undefined;
    prf(&master, "server finished", &hash, &expect);
    if (plain.len != 16 or plain[0] != 0x14 or !std.mem.eql(u8, plain[4..16], &expect)) return fail("bad server finished");
    return session;
}
