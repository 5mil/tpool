const compat = @import("compat.zig");
const std = @import("std");

const control_port: u16 = 7835;

const Control = struct {
    stream: compat.net.Stream,
    local_port: u16,
    host: [80]u8 = @splat(0),
    host_len: usize = 0,
    stop: bool = false,
};

var controls: [4]?*Control = .{ null, null, null, null };

pub const Result = struct {
    ok: bool = false,
    port: u16 = 0,
    why_buf: [180]u8 = @splat(0),
    why_len: usize = 0,

    pub fn text(self: *const Result) []const u8 {
        return self.why_buf[0..self.why_len];
    }
};

fn failed(msg: []const u8) Result {
    var r = Result{};
    r.why_len = @min(msg.len, r.why_buf.len);
    @memcpy(r.why_buf[0..r.why_len], msg[0..r.why_len]);
    return r;
}

fn readFrame(stream: *compat.net.Stream, buf: []u8) ![]u8 {
    var n: usize = 0;
    while (n < buf.len) {
        var one: [1]u8 = undefined;
        const got = stream.read(&one) catch return error.Closed;
        if (got == 0) return error.Closed;
        if (one[0] == 0) return buf[0..n];
        buf[n] = one[0];
        n += 1;
    }
    return error.FrameTooLong;
}

fn helloPort(frame: []const u8) ?u16 {
    const key = "\"Hello\":";
    const at = std.mem.indexOf(u8, frame, key) orelse return null;
    var i = at + key.len;
    while (i < frame.len and (frame[i] == ' ' or frame[i] == '"')) i += 1;
    var n: u16 = 0;
    var any = false;
    while (i < frame.len and frame[i] >= '0' and frame[i] <= '9') : (i += 1) {
        any = true;
        n = n * 10 + (frame[i] - '0');
    }
    return if (any and n > 0) n else null;
}

fn connectionId(frame: []const u8, out: []u8) ?[]u8 {
    const key = "\"Connection\":\"";
    const at = std.mem.indexOf(u8, frame, key) orelse return null;
    var i = at + key.len;
    var n: usize = 0;
    while (i < frame.len and frame[i] != '"' and n < out.len) : (i += 1) {
        out[n] = frame[i];
        n += 1;
    }
    if (n < 8) return null;
    return out[0..n];
}

fn errorText(frame: []const u8, out: []u8) ?[]u8 {
    const key = "\"Error\":\"";
    const at = std.mem.indexOf(u8, frame, key) orelse return null;
    var i = at + key.len;
    var n: usize = 0;
    while (i < frame.len and frame[i] != '"' and n < out.len) : (i += 1) {
        out[n] = frame[i];
        n += 1;
    }
    return out[0..n];
}

const Pair = struct {
    remote: compat.net.Stream,
    local: compat.net.Stream,
    lock: compat.Mutex = .{},
    closed: bool = false,
};

fn pump(pair: *Pair, from_remote: bool) void {
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = (if (from_remote) pair.remote.read(&buf) else pair.local.read(&buf)) catch break;
        if (n == 0) break;
        (if (from_remote) pair.local.writeAll(buf[0..n]) else pair.remote.writeAll(buf[0..n])) catch break;
    }
    pair.lock.lock();
    if (!pair.closed) {
        pair.closed = true;
        pair.remote.close();
        pair.local.close();
    }
    pair.lock.unlock();
}

fn bridge(ctrl: *Control, id: []u8) void {
    defer std.heap.page_allocator.free(id);
    const remote = compat.net.connectHost(ctrl.host[0..ctrl.host_len], control_port) catch return;
    var accept_buf: [96]u8 = undefined;
    const accept = std.fmt.bufPrint(&accept_buf, "{{\"Accept\":\"{s}\"}}\x00", .{id}) catch {
        remote.close();
        return;
    };
    remote.writeAll(accept) catch {
        remote.close();
        return;
    };
    var local: ?compat.net.Stream = null;
    var tries: usize = 0;
    while (tries < 20) : (tries += 1) {
        if (compat.net.connectHost("127.0.0.1", ctrl.local_port)) |stream| {
            local = stream;
            break;
        } else |_| {}
        compat.time.sleep(250 * std.time.ns_per_ms);
    }
    const got = local orelse {
        remote.close();
        return;
    };
    const pair = std.heap.page_allocator.create(Pair) catch {
        remote.close();
        got.close();
        return;
    };
    pair.* = .{ .remote = remote, .local = got };
    const a = std.Thread.spawn(.{}, pump, .{ pair, true }) catch {
        remote.close();
        got.close();
        return;
    };
    const b = std.Thread.spawn(.{}, pump, .{ pair, false }) catch {
        pair.closed = true;
        remote.close();
        got.close();
        a.join();
        return;
    };
    a.join();
    b.join();
}

fn controlLoop(ctrl: *Control) void {
    var buf: [256]u8 = undefined;
    var idbuf: [48]u8 = undefined;
    while (!ctrl.stop) {
        const frame = readFrame(&ctrl.stream, &buf) catch break;
        if (std.mem.eql(u8, frame, "\"Heartbeat\"") or std.mem.indexOf(u8, frame, "Heartbeat") != null and frame.len < 24) continue;
        if (connectionId(frame, &idbuf)) |id| {
            const owned = std.heap.page_allocator.dupe(u8, id) catch continue;
            const thread = std.Thread.spawn(.{}, bridge, .{ ctrl, owned }) catch {
                std.heap.page_allocator.free(owned);
                continue;
            };
            thread.detach();
        }
    }
    ctrl.stream.close();
}

pub fn publish(local_port: u16, host: []const u8) Result {
    if (local_port == 0 or host.len == 0 or host.len > 80) return failed("mining relay needs a local port");
    const stream = compat.net.connectHost(host, control_port) catch return failed("could not reach bore.pub:7835. The mining port stays local.");
    var held = stream;
    var hello_buf: [32]u8 = undefined;
    const hello = std.fmt.bufPrint(&hello_buf, "{{\"Hello\":0}}\x00", .{}) catch {
        stream.close();
        return failed("mining relay could not write the hello");
    };
    held.writeAll(hello) catch {
        held.close();
        return failed("bore.pub closed before the hello");
    };
    var frame_buf: [256]u8 = undefined;
    const frame = readFrame(&held, &frame_buf) catch {
        held.close();
        return failed("bore.pub did not answer. The mining port stays local.");
    };
    if (std.mem.indexOf(u8, frame, "Challenge") != null) {
        held.close();
        return failed("bore.pub asked for a secret this build does not have");
    }
    var why_tmp: [160]u8 = undefined;
    if (errorText(frame, &why_tmp)) |msg| {
        if (msg.len > 0) {
            held.close();
            return failed(msg);
        }
    }
    const public_port = helloPort(frame) orelse {
        held.close();
        var shown: [180]u8 = undefined;
        const n = @min(frame.len, 120);
        const text = std.fmt.bufPrint(&shown, "bore.pub sent {s}", .{frame[0..n]}) catch return failed("bore.pub did not assign a port");
        return failed(text);
    };
    const ctrl = std.heap.page_allocator.create(Control) catch {
        held.close();
        return failed("no memory for the mining relay");
    };
    ctrl.* = .{ .stream = held, .local_port = local_port };
    ctrl.host_len = host.len;
    @memcpy(ctrl.host[0..host.len], host);
    var slot: ?usize = null;
    for (controls, 0..) |c, i| {
        if (c == null) {
            slot = i;
            break;
        }
    }
    if (slot == null) {
        held.close();
        return failed("four mining relays are already open");
    }
    controls[slot.?] = ctrl;
    const thread = std.Thread.spawn(.{}, controlLoop, .{ctrl}) catch {
            controls[slot.?] = null;
            held.close();
            return failed("the mining relay thread did not start");
        };
    thread.detach();
    var r = Result{ .ok = true, .port = public_port };
    if (std.fmt.bufPrint(&r.why_buf, "stratum+tcp://{s}:{d}", .{ host, public_port })) |text| {
        r.why_len = text.len;
    } else |_| {
        r.why_len = 9;
        @memcpy(r.why_buf[0..9], "published");
    }
    return r;
}

pub fn closeAll() void {
    for (&controls) |*slot| {
        if (slot.*) |ctrl| {
            ctrl.stop = true;
            ctrl.stream.close();
            slot.* = null;
        }
    }
}

fn echo(port: u16) void {
    const addr = compat.net.Address.parseIp4("127.0.0.1", port) catch return;
    var server = addr.listen(.{}) catch return;
    while (true) {
        var conn = server.accept() catch continue;
        var buf: [64]u8 = undefined;
        _ = conn.stream.read(&buf) catch 0;
        conn.stream.writeAll("pong-from-local") catch {};
        conn.stream.close();
    }
}

pub fn main(init: std.process.Init) !void {
    compat.bind(init);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();
    const port_s = args.next() orelse "39334";
    const port = try std.fmt.parseInt(u16, port_s, 10);
    const echo_thread = try std.Thread.spawn(.{}, echo, .{port});
    echo_thread.detach();
    compat.time.sleep(200 * std.time.ns_per_ms);
    const opened = publish(port, "bore.pub");
    if (!opened.ok) {
        std.debug.print("FAIL {s}\n", .{opened.text()});
        std.process.exit(1);
    }
    std.debug.print("LISTENING {s}\n", .{opened.text()});
    while (true) compat.time.sleep(std.time.ns_per_s);
}
