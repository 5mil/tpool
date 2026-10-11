const compat = @import("compat.zig");
const std = @import("std");

pub const Party = struct {
    name: [80]u8 = undefined,
    name_len: usize = 0,
    pass: [16]u8 = undefined,
    pass_len: usize = 0,
    round: u64 = 0,
    life: u64 = 0,
    blocks: u64 = 0,
    paid: u64 = 0,
    house: u64 = 0,
    stale: u64 = 0,
    online: u16 = 0,
    last_height: u32 = 0,
    window_diff: u64 = 0,
    window_start: i64 = 0,
};

pub var parties: [32]Party = undefined;
pub var count: usize = 0;
const fee_pct: u64 = 1;

pub const Gate = enum { joined, denied };

fn put(dst: []u8, src: []const u8) usize {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

fn hashSecret(secret: []const u8, out: []u8) usize {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(secret);
    const digest = hasher.finalResult();
    const digits = "0123456789abcdef";
    const n = @min(out.len / 2, digest.len);
    for (digest[0..n], 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0xf];
    }
    return n * 2;
}

fn find(name: []const u8) ?*Party {
    for (parties[0..count]) |*p| {
        if (std.mem.eql(u8, p.name[0..p.name_len], name)) return p;
    }
    return null;
}

pub fn of(name: []const u8) *Party {
    if (find(name)) |p| return p;
    if (count >= parties.len) return &parties[0];
    const p = &parties[count];
    count += 1;
    p.* = .{};
    p.name_len = put(&p.name, name);
    p.window_start = compat.time.timestamp();
    return p;
}

/// First miner to name a party may set a secret. Later miners must match it.
/// An empty secret joins only an open party, or creates one.
pub fn enter(name: []const u8, secret: []const u8) Gate {
    if (find(name)) |p| {
        if (p.pass_len == 0) return .joined;
        if (secret.len == 0) return .denied;
        var got: [16]u8 = undefined;
        const n = hashSecret(secret, &got);
        if (n == p.pass_len and std.mem.eql(u8, p.pass[0..p.pass_len], got[0..n])) return .joined;
        return .denied;
    }
    const p = of(name);
    if (secret.len > 0) p.pass_len = hashSecret(secret, &p.pass);
    return .joined;
}

pub fn credit(name: []const u8, diff: u64) void {
    const p = of(name);
    const now = compat.time.timestamp();
    if (p.window_start == 0 or now - p.window_start > 300) {
        p.window_start = now;
        p.window_diff = 0;
    }
    p.round += diff;
    p.life += diff;
    p.window_diff += diff;
}

pub fn markStale(name: []const u8) void {
    of(name).stale += 1;
}

pub fn rate(p: *const Party) u64 {
    if (p.window_start == 0) return 0;
    const elapsed = compat.time.timestamp() - p.window_start;
    if (elapsed <= 0) return p.window_diff;
    return p.window_diff / @as(u64, @intCast(elapsed));
}

/// House keeps `fee_pct`. The rest is split by round shares. Dust stays unpaid.
/// This does not touch a party. `split` records the result.
pub fn divideReward(reward: u64, shares: []const u64, out: []u64) struct { paid: u64, house: u64 } {
    for (out) |*o| o.* = 0;
    var total: u64 = 0;
    for (shares) |s| total += s;
    if (total == 0 or reward == 0) return .{ .paid = 0, .house = 0 };
    const keep = reward * fee_pct / 100;
    const pay = reward - keep;
    var given: u64 = 0;
    for (shares, 0..) |s, i| {
        if (i >= out.len) break;
        const cut = pay * s / total;
        out[i] = cut;
        given += cut;
    }
    return .{ .paid = given, .house = keep };
}

/// Split `reward` by round shares. House keeps fee_pct. Resets the round.
pub fn split(reward: u64, party_name: []const u8, shares: []const u64, out: []u64, height: u32) u64 {
    const part = divideReward(reward, shares, out);
    if (part.paid == 0 and part.house == 0) return 0;
    const p = of(party_name);
    p.blocks += 1;
    p.paid += part.paid;
    p.house += part.house;
    p.round = 0;
    p.last_height = height;
    return part.paid;
}

pub fn line(buf: []u8) []u8 {
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer out.deinit();
    if (count == 0) return std.fmt.bufPrint(buf, "parties  none yet\n", .{}) catch buf[0..0];
    for (parties[0..count]) |p| {
        out.print("{s}  {s}  online {d}  round {d}  ~{d} diff/s  life {d}  blocks {d}  paid {d}  house {d}  stale {d}  height {d}  fee {d}%\n", .{
            p.name[0..p.name_len],
            if (p.pass_len == 0) "open" else "locked",
            p.online,
            p.round,
            rate(&p),
            p.life,
            p.blocks,
            p.paid,
            p.house,
            p.stale,
            p.last_height,
            fee_pct,
        }) catch {};
    }
    const n = @min(out.items.len, buf.len);
    @memcpy(buf[0..n], out.items[0..n]);
    return buf[0..n];
}

pub fn load(alloc: std.mem.Allocator) void {
    const raw = compat.fs.cwd().readFileAlloc(alloc, "parties.ledger", 1 << 16) catch return;
    defer alloc.free(raw);
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |row| {
        if (row.len < 2 or row[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, row, '\t');
        const name = parts.next() orelse continue;
        const pass = parts.next() orelse "";
        const p = of(name);
        p.pass_len = put(&p.pass, pass);
        p.blocks = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        p.paid = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        p.house = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        p.stale = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
        p.last_height = std.fmt.parseInt(u32, parts.next() orelse "0", 10) catch 0;
        p.life = std.fmt.parseInt(u64, parts.next() orelse "0", 10) catch 0;
    }
}

pub fn save(alloc: std.mem.Allocator) void {
    var buf = std.array_list.Managed(u8).init(alloc);
    defer buf.deinit();
    buf.appendSlice("# party  secret  blocks  paid  house  stale  height  life\n") catch return;
    for (parties[0..count]) |p| {
        buf.print("{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\n", .{
            p.name[0..p.name_len],
            p.pass[0..p.pass_len],
            p.blocks,
            p.paid,
            p.house,
            p.stale,
            p.last_height,
            p.life,
        }) catch return;
    }
    var file = compat.fs.cwd().createFile("parties.ledger.tmp", .{}) catch return;
    file.writeAll(buf.items) catch {
        file.close();
        return;
    };
    file.close();
    compat.fs.cwd().rename("parties.ledger.tmp", "parties.ledger") catch {};
}
