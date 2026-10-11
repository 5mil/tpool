const compat = @import("compat.zig");
const std = @import("std");
const pool = @import("pool.zig");
const ops = @import("ops.zig");

const rooms = [_][]const u8{ "Lobby", "Thirtysomething", "Computer Help", "Sports Bar", "New Member Lounge" };

const User = struct { id: u32, name: []u8, salt: []u8, hash: []u8, created: i64 };
const Session = struct { token: []u8, user_id: u32, seen: i64 };
const Message = struct { id: u32, room: []u8, user_id: u32, body: []u8, created: i64 };
const Mail = struct { id: u32, from_id: u32, to_id: u32, subject: []u8, body: []u8, unread: bool, created: i64 };

const Store = struct {
    alloc: std.mem.Allocator,
    lock: compat.Mutex = .{},
    users: std.array_list.Managed(User),
    sessions: std.array_list.Managed(Session),
    messages: std.array_list.Managed(Message),
    mail: std.array_list.Managed(Mail),
    next_user: u32 = 1,
    next_msg: u32 = 1,
    next_mail: u32 = 1,
    path: []const u8,

    fn init(alloc: std.mem.Allocator, path: []const u8) Store {
        return .{
            .alloc = alloc,
            .users = std.array_list.Managed(User).init(alloc),
            .sessions = std.array_list.Managed(Session).init(alloc),
            .messages = std.array_list.Managed(Message).init(alloc),
            .mail = std.array_list.Managed(Mail).init(alloc),
            .path = path,
        };
    }

    fn load(self: *Store) !void {
        const file = compat.fs.cwd().openFile(self.path, .{}) catch return;
        defer file.close();
        const raw = try file.readToEndAlloc(self.alloc, 8 << 20);
        defer self.alloc.free(raw);
        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line| {
            if (line.len < 2) continue;
            var parts = std.mem.splitScalar(u8, line, '\t');
            const kind = parts.next() orelse continue;
            if (std.mem.eql(u8, kind, "user")) {
                const id = try std.fmt.parseInt(u32, parts.next() orelse continue, 10);
                try self.users.append(.{
                    .id = id,
                    .name = try self.alloc.dupe(u8, parts.next() orelse continue),
                    .salt = try self.alloc.dupe(u8, parts.next() orelse continue),
                    .hash = try self.alloc.dupe(u8, parts.next() orelse continue),
                    .created = try std.fmt.parseInt(i64, parts.next() orelse "0", 10),
                });
                self.next_user = @max(self.next_user, id + 1);
            } else if (std.mem.eql(u8, kind, "msg")) {
                const id = try std.fmt.parseInt(u32, parts.next() orelse continue, 10);
                try self.messages.append(.{
                    .id = id,
                    .room = try self.alloc.dupe(u8, parts.next() orelse continue),
                    .user_id = try std.fmt.parseInt(u32, parts.next() orelse "0", 10),
                    .body = try unescape(self.alloc, parts.next() orelse ""),
                    .created = try std.fmt.parseInt(i64, parts.next() orelse "0", 10),
                });
                self.next_msg = @max(self.next_msg, id + 1);
            } else if (std.mem.eql(u8, kind, "mail")) {
                const id = try std.fmt.parseInt(u32, parts.next() orelse continue, 10);
                try self.mail.append(.{
                    .id = id,
                    .from_id = try std.fmt.parseInt(u32, parts.next() orelse "0", 10),
                    .to_id = try std.fmt.parseInt(u32, parts.next() orelse "0", 10),
                    .subject = try unescape(self.alloc, parts.next() orelse ""),
                    .body = try unescape(self.alloc, parts.next() orelse ""),
                    .unread = std.mem.eql(u8, parts.next() orelse "1", "1"),
                    .created = try std.fmt.parseInt(i64, parts.next() orelse "0", 10),
                });
                self.next_mail = @max(self.next_mail, id + 1);
            }
        }
    }

    fn save(self: *Store) !void {
        var buf = std.array_list.Managed(u8).init(self.alloc);
        defer buf.deinit();
        for (self.users.items) |u| {
            try buf.print("user\t{d}\t{s}\t{s}\t{s}\t{d}\n", .{ u.id, u.name, u.salt, u.hash, u.created });
        }
        for (self.messages.items) |m| {
            const body = try escape(self.alloc, m.body);
            defer self.alloc.free(body);
            try buf.print("msg\t{d}\t{s}\t{d}\t{s}\t{d}\n", .{ m.id, m.room, m.user_id, body, m.created });
        }
        for (self.mail.items) |m| {
            const subject = try escape(self.alloc, m.subject);
            defer self.alloc.free(subject);
            const body = try escape(self.alloc, m.body);
            defer self.alloc.free(body);
            try buf.print("mail\t{d}\t{d}\t{d}\t{s}\t{s}\t{s}\t{d}\n", .{ m.id, m.from_id, m.to_id, subject, body, if (m.unread) "1" else "0", m.created });
        }
        try atomicWrite(self.alloc, self.path, buf.items);
    }
};

fn atomicWrite(alloc: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const tmp = try std.fmt.allocPrint(alloc, "{s}.tmp", .{path});
    defer alloc.free(tmp);
    var file = try compat.fs.cwd().createFile(tmp, .{});
    try file.writeAll(data);
    file.close();
    compat.fs.cwd().rename(tmp, path) catch |err| {
        file = compat.fs.cwd().createFile(path, .{}) catch return err;
        defer file.close();
        try file.writeAll(data);
    };
}

fn escape(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(alloc);
    for (text) |c| {
        if (c == '\\' or c == '\t' or c == '\n' or c == '\r') try out.append('\\');
        try out.append(if (c == '\n' or c == '\r' or c == '\t') ' ' else c);
    }
    return out.toOwnedSlice();
}

fn unescape(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    return alloc.dupe(u8, text);
}

fn validName(name: []const u8) bool {
    if (name.len < 3 or name.len > 16) return false;
    if (!std.ascii.isAlphabetic(name[0])) return false;
    for (name) |c| if (!std.ascii.isAlphanumeric(c)) return false;
    return true;
}

fn hashPassword(password: []const u8, salt: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.pwhash.pbkdf2(&out, password, salt, 120_000, std.crypto.auth.hmac.sha2.HmacSha256) catch unreachable;
    return out;
}

fn hex32(raw: [32]u8) [64]u8 {
    const digits = "0123456789abcdef";
    var out: [64]u8 = undefined;
    for (raw, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0xf];
    }
    return out;
}

fn fillRandom(buf: []u8) void {
    var rng = std.Random.DefaultPrng.init(@bitCast(compat.time.timestamp() +% @as(i64, @intCast(buf.len))));
    rng.random().bytes(buf);
}

fn hexAlloc(alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
    const digits = "0123456789abcdef";
    var out = try alloc.alloc(u8, raw.len * 2);
    for (raw, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0xf];
    }
    return out;
}

fn findUser(store: *Store, name: []const u8) ?usize {
    for (store.users.items, 0..) |u, i| if (std.ascii.eqlIgnoreCase(u.name, name)) return i;
    return null;
}

fn userById(store: *Store, id: u32) ?User {
    for (store.users.items) |u| if (u.id == id) return u;
    return null;
}

fn auth(store: *Store, header: []const u8) ?User {
    const prefix = "Bearer ";
    if (!std.mem.startsWith(u8, header, prefix)) return null;
    const token = header[prefix.len..];
    const now = compat.time.timestamp();
    for (store.sessions.items) |*s| {
        if (now - s.seen > 60 * 60 * 24 * 7) continue;
        if (std.mem.eql(u8, s.token, token)) {
            s.seen = now;
            return userById(store, s.user_id);
        }
    }
    return null;
}

fn jsonString(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(alloc);
    try out.append('"');
    for (text) |c| {
        if (c == '"' or c == '\\') try out.append('\\');
        try out.append(if (c < 32) ' ' else c);
    }
    try out.append('"');
    return out.toOwnedSlice();
}

fn fixedEqual(a: []const u8, b: []const u8) bool {
    var diff: u8 = @intFromBool(a.len != b.len);
    const n = @min(a.len, b.len);
    for (a[0..n], b[0..n]) |x, y| diff |= x ^ y;
    return diff == 0 and a.len == b.len;
}

fn safeRepo(repo: []const u8) bool {
    if (repo.len < 20 or repo.len > 120) return false;
    if (std.mem.indexOf(u8, repo, "..") != null) return false;
    if (std.mem.indexOfAny(u8, repo, " \t\r\n'\"`;$") != null) return false;
    return std.mem.startsWith(u8, repo, "https://github.com/") or std.mem.startsWith(u8, repo, "https://gitlab.com/");
}

fn formOrJson(body: []const u8, key: []const u8, alloc: std.mem.Allocator) ![]u8 {
    if (std.mem.indexOf(u8, body, "\":\"")) |_| return field(body, key, alloc);
    var pat: [40]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "{s}=", .{key}) catch return alloc.dupe(u8, "");
    const at = std.mem.indexOf(u8, body, p) orelse return alloc.dupe(u8, "");
    const rest = body[at + p.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '&') orelse rest.len;
    return alloc.dupe(u8, rest[0..end]);
}

fn field(body: []const u8, key: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var pat_buf: [40]u8 = undefined;
    const pat = std.fmt.bufPrint(&pat_buf, "\"{s}\":\"", .{key}) catch return alloc.dupe(u8, "");
    const start = std.mem.indexOf(u8, body, pat) orelse return alloc.dupe(u8, "");
    var i = start + pat.len;
    var out = std.array_list.Managed(u8).init(alloc);
    while (i < body.len and body[i] != '"') : (i += 1) {
        if (body[i] == '\\' and i + 1 < body.len) i += 1;
        try out.append(body[i]);
    }
    return out.toOwnedSlice();
}

fn handle(store: *Store, alloc: std.mem.Allocator, method: []const u8, path: []const u8, headers: []const u8, body: []const u8) ![]u8 {
    if (std.mem.eql(u8, path, "/admin")) {
        const page = "<html><body style=\"background:#1a2420;color:#d7d2c8;font-family:Georgia,serif\"><h1>Pool admin</h1><p>Paste a compatible coin repo. The host clones it and points the pool at that name.</p><form method=\"POST\" action=\"/api/admin/coin\">Admin token <input name=\"token\"><br>Repo <input name=\"repo\" size=\"60\" placeholder=\"https://github.com/5mil/orthal.git\"><br><button>Build pool</button></form></body></html>";
        return std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ page.len, page });
    }
    if (std.mem.eql(u8, path, "/api/admin/coin")) {
        const token = formOrJson(body, "token", alloc) catch "";
        const repo = formOrJson(body, "repo", alloc) catch "";
        const expected = compat.getEnv(alloc, "THIMBLE_ADMIN") catch "";
        defer if (expected.len > 0) alloc.free(expected);
        if (expected.len < 8 or !fixedEqual(token, expected) or !safeRepo(repo)) {
            const payload = "{\"ok\":false,\"error\":\"Admin token missing or repo not allowed.\"}";
            return std.fmt.allocPrint(alloc, "HTTP/1.1 403 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
        }
        const name = compat.fs.path.stem(repo);
        const dest = try std.fmt.allocPrint(alloc, "coin-src/{s}", .{name});
        var child = compat.Child.init(&.{ "git", "clone", "--depth", "1", repo, dest }, alloc);
        const term = child.spawnAndWait() catch {
            const payload = "{\"ok\":false,\"error\":\"git failed to start\"}";
            return std.fmt.allocPrint(alloc, "HTTP/1.1 500 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
        };
        if (term != .Exited or term.Exited != 0) {
            const payload = "{\"ok\":false,\"error\":\"clone failed\"}";
            return std.fmt.allocPrint(alloc, "HTTP/1.1 502 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
        }
        var file = try compat.fs.cwd().createFile("coin.cfg", .{});
        defer file.close();
        try file.print("name={s}\nrepo={s}\npath={s}\n", .{ name, repo, dest });
        const payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"coin\":\"{s}\",\"path\":\"{s}\"}}", .{ name, dest });
        return std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
    }
    if (std.mem.eql(u8, path, "/api/doctor") or std.mem.eql(u8, path, "/api/check")) {
        const report = ops.run(alloc, .{ .probe = true, .config = true, .live = true, .files = true, .expect_signon = true, .expect_listen = true });
        var text_buf: [16000]u8 = undefined;
        const n = ops.format(&text_buf, &report);
        const payload = text_buf[0..n];
        return std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
    }
    if (std.mem.eql(u8, path, "/api/health")) {
        store.lock.lock();
        const users = store.users.items.len;
        const sessions = store.sessions.items.len;
        const messages = store.messages.items.len;
        store.lock.unlock();
        pool.pool.lock.lock();
        const accepted = pool.pool.accepted;
        const workers = pool.pool.workers.items.len;
        pool.pool.lock.unlock();
        const payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"users\":{d},\"sessions\":{d},\"messages\":{d},\"poolAccepted\":{d},\"poolWorkers\":{d}}}", .{ users, sessions, messages, accepted, workers });
        return std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
    }
    if (std.mem.eql(u8, path, "/api/pool")) {
        const payload = try pool.pool.statusJson(alloc);
        return std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ payload.len, payload });
    }
    if (std.mem.eql(u8, method, "GET") and (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html"))) {
        const page = compat.fs.cwd().readFileAlloc(alloc, "index.html", 1 << 20) catch "<h1>index.html missing</h1>";
        return std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ page.len, page });
    }
    const auth_header = blk: {
        var it = std.mem.splitSequence(u8, headers, "\r\n");
        while (it.next()) |line| if (std.ascii.startsWithIgnoreCase(line, "Authorization:")) break :blk std.mem.trim(u8, line[14..], " ");
        break :blk "";
    };
    var code: u16 = 200;
    var payload: []u8 = undefined;
    store.lock.lock();
    defer store.lock.unlock();
    if (std.mem.eql(u8, path, "/api/rooms")) {
        payload = try alloc.dupe(u8, "{\"rooms\":[\"Lobby\",\"Thirtysomething\",\"Computer Help\",\"Sports Bar\",\"New Member Lounge\"]}");
    } else if (std.mem.eql(u8, path, "/api/signup") or std.mem.eql(u8, path, "/api/login")) {
        const name = try field(body, "screenName", alloc);
        const password = try field(body, "password", alloc);
        defer alloc.free(name);
        defer alloc.free(password);
        if (std.mem.eql(u8, path, "/api/signup")) {
            if (!validName(name)) {
                code = 400;
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Screen names are 3 to 16 letters and numbers, starting with a letter.\"}");
            } else if (password.len < 4) {
                code = 400;
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Password needs at least 4 characters.\"}");
            } else if (findUser(store, name) != null) {
                code = 409;
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"That screen name is taken.\"}");
            } else {
                var salt_raw: [16]u8 = undefined;
                fillRandom(&salt_raw);
                const salt = try hexAlloc(alloc, &salt_raw);
                const digest = hex32(hashPassword(password, salt));
                const id = store.next_user;
                store.next_user += 1;
                try store.users.append(.{ .id = id, .name = try alloc.dupe(u8, name), .salt = salt, .hash = try alloc.dupe(u8, &digest), .created = compat.time.timestamp() });
                try store.mail.append(.{ .id = store.next_mail, .from_id = id, .to_id = id, .subject = try alloc.dupe(u8, "You've Got Mail"), .body = try alloc.dupe(u8, "Welcome to Thimble. You have a screen name. The lobby is open, and the mail light is on."), .unread = true, .created = compat.time.timestamp() });
                store.next_mail += 1;
                var token_raw: [24]u8 = undefined;
                fillRandom(&token_raw);
                const token = try hexAlloc(alloc, &token_raw);
                try store.sessions.append(.{ .token = try alloc.dupe(u8, token), .user_id = id, .seen = compat.time.timestamp() });
                try store.save();
                payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"token\":\"{s}\",\"screenName\":{s}}}", .{ token, try jsonString(alloc, name) });
            }
        } else if (findUser(store, name)) |idx| {
            const user = store.users.items[idx];
            const digest = hex32(hashPassword(password, user.salt));
            if (!std.mem.eql(u8, user.hash, &digest)) {
                code = 401;
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Password does not match.\"}");
            } else {
                var token_raw: [24]u8 = undefined;
                fillRandom(&token_raw);
                const token = try hexAlloc(alloc, &token_raw);
                try store.sessions.append(.{ .token = try alloc.dupe(u8, token), .user_id = user.id, .seen = compat.time.timestamp() });
                try store.save();
                payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"token\":\"{s}\",\"screenName\":{s}}}", .{ token, try jsonString(alloc, user.name) });
            }
        } else {
            code = 401;
            payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"That screen name is not on this server.\"}");
        }
    } else if (auth(store, auth_header)) |user| {
        if (std.mem.startsWith(u8, path, "/api/messages") and std.mem.eql(u8, method, "GET")) {
            const room = queryRoom(path);
            const since = querySince(path);
            var out = std.array_list.Managed(u8).init(alloc);
            try out.appendSlice("{\"messages\":[");
            var first = true;
            for (store.messages.items) |m| {
                if (!std.mem.eql(u8, m.room, room) or m.id <= since) continue;
                const sender = userById(store, m.user_id) orelse continue;
                if (!first) try out.append(',');
                first = false;
                try out.print("{{\"id\":{d},\"name\":{s},\"body\":{s},\"created\":{d}}}", .{ m.id, try jsonString(alloc, sender.name), try jsonString(alloc, m.body), m.created });
            }
            try out.appendSlice("],\"online\":[");
            var seen_first = true;
            const now = compat.time.timestamp();
            for (store.sessions.items) |s| {
                if (now - s.seen > 90) continue;
                const who = userById(store, s.user_id) orelse continue;
                if (!seen_first) try out.append(',');
                seen_first = false;
                try out.appendSlice(try jsonString(alloc, who.name));
            }
            var unread: u32 = 0;
            for (store.mail.items) |m| if (m.to_id == user.id and m.unread) {
                unread += 1;
            };
            try out.print("],\"unread\":{d}}}", .{unread});
            payload = try out.toOwnedSlice();
        } else if (std.mem.eql(u8, path, "/api/messages")) {
            const room = try field(body, "room", alloc);
            const text = try field(body, "text", alloc);
            var known = false;
            for (rooms) |r| if (std.mem.eql(u8, r, room)) {
                known = true;
            };
            if (!known or text.len == 0) {
                code = 400;
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Say something in a real room.\"}");
            } else {
                const id = store.next_msg;
                store.next_msg += 1;
                try store.messages.append(.{ .id = id, .room = try alloc.dupe(u8, room), .user_id = user.id, .body = try alloc.dupe(u8, text[0..@min(text.len, 240)]), .created = compat.time.timestamp() });
                try store.save();
                payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"id\":{d}}}", .{id});
            }
        } else if (std.mem.eql(u8, path, "/api/mail") and std.mem.eql(u8, method, "GET")) {
            var out = std.array_list.Managed(u8).init(alloc);
            try out.appendSlice("{\"mail\":[");
            var first = true;
            var i: usize = store.mail.items.len;
            while (i > 0) {
                i -= 1;
                const m = store.mail.items[i];
                if (m.to_id != user.id) continue;
                const sender = userById(store, m.from_id) orelse continue;
                if (!first) try out.append(',');
                first = false;
                try out.print("{{\"id\":{d},\"sender\":{s},\"subject\":{s},\"body\":{s},\"unread\":{s}}}", .{ m.id, try jsonString(alloc, sender.name), try jsonString(alloc, m.subject), try jsonString(alloc, m.body), if (m.unread) "true" else "false" });
                store.mail.items[i].unread = false;
            }
            try out.appendSlice("]}");
            try store.save();
            payload = try out.toOwnedSlice();
        } else if (std.mem.eql(u8, path, "/api/mail")) {
            const to_name = try field(body, "to", alloc);
            const subject = try field(body, "subject", alloc);
            const text = try field(body, "body", alloc);
            if (findUser(store, to_name)) |idx| {
                try store.mail.append(.{ .id = store.next_mail, .from_id = user.id, .to_id = store.users.items[idx].id, .subject = try alloc.dupe(u8, if (subject.len == 0) "(no subject)" else subject), .body = try alloc.dupe(u8, text), .unread = true, .created = compat.time.timestamp() });
                store.next_mail += 1;
                try store.save();
                payload = try alloc.dupe(u8, "{\"ok\":true}");
            } else {
                code = 404;
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"No member by that screen name.\"}");
            }
        } else {
            code = 404;
            payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Not found.\"}");
        }
    } else if (std.mem.startsWith(u8, path, "/api/")) {
        code = 401;
        payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Sign on first.\"}");
    } else {
        code = 404;
        payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Not found.\"}");
    }
    return std.fmt.allocPrint(alloc, "HTTP/1.1 {d} OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ code, payload.len, payload });
}

fn queryRoom(path: []const u8) []const u8 {
    const key = "room=";
    const at = std.mem.indexOf(u8, path, key) orelse return "Lobby";
    const rest = path[at + key.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '&') orelse rest.len;
    const raw = rest[0..end];
    if (std.mem.eql(u8, raw, "Computer+Help") or std.mem.eql(u8, raw, "Computer%20Help")) return "Computer Help";
    if (std.mem.eql(u8, raw, "Sports+Bar") or std.mem.eql(u8, raw, "Sports%20Bar")) return "Sports Bar";
    if (std.mem.eql(u8, raw, "New+Member+Lounge") or std.mem.eql(u8, raw, "New%20Member%20Lounge")) return "New Member Lounge";
    for (rooms) |r| if (std.mem.eql(u8, r, raw)) return r;
    return "Lobby";
}

fn querySince(path: []const u8) u32 {
    const key = "since=";
    const at = std.mem.indexOf(u8, path, key) orelse return 0;
    const rest = path[at + key.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '&') orelse rest.len;
    return std.fmt.parseInt(u32, rest[0..end], 10) catch 0;
}

fn serveClient(store: *Store, conn: compat.net.Server.Connection) void {
    defer conn.stream.close();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var buf: [16384]u8 = undefined;
    const n = conn.stream.read(&buf) catch return;
    const req = buf[0..n];
    const line_end = std.mem.indexOf(u8, req, "\r\n") orelse return;
    var line = std.mem.splitScalar(u8, req[0..line_end], ' ');
    const method = line.next() orelse return;
    const target = line.next() orelse return;
    const header_end = std.mem.indexOf(u8, req, "\r\n\r\n") orelse return;
    const headers = req[0 .. header_end + 2];
    const body = req[header_end + 4 ..];
    if (std.mem.eql(u8, method, "OPTIONS")) {
        _ = conn.stream.writeAll("HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nContent-Length: 0\r\nConnection: close\r\n\r\n") catch return;
        return;
    }
    const response = handle(store, alloc, method, target, headers, body) catch return;
    _ = conn.stream.writeAll(response) catch return;
}

fn selftest() !void {
    var store = Store.init(std.heap.page_allocator, "thimble-selftest.db");
    const signup = try handle(&store, std.heap.page_allocator, "POST", "/api/signup", "", "{\"screenName\":\"ModemQueen\",\"password\":\"dialup\"}");
    if (std.mem.indexOf(u8, signup, "\"ok\":true") == null) return error.SignupFailed;
    const token_at = std.mem.indexOf(u8, signup, "\"token\":\"") orelse return error.NoToken;
    const token = signup[token_at + 9 .. token_at + 9 + 48];
    var auth_buf: [80]u8 = undefined;
    const header = try std.fmt.bufPrint(&auth_buf, "Authorization: Bearer {s}", .{token});
    const posted = try handle(&store, std.heap.page_allocator, "POST", "/api/messages", header, "{\"room\":\"Lobby\",\"text\":\"wb from the kitchen phone\"}");
    if (std.mem.indexOf(u8, posted, "\"ok\":true") == null) return error.PostFailed;
    const listed = try handle(&store, std.heap.page_allocator, "GET", "/api/messages?room=Lobby&since=0", header, "");
    if (std.mem.indexOf(u8, listed, "kitchen phone") == null) return error.MissingChat;
    _ = try handle(&store, std.heap.page_allocator, "POST", "/api/signup", "", "{\"screenName\":\"CoolDude95\",\"password\":\"lobby\"}");
    const mailed = try handle(&store, std.heap.page_allocator, "POST", "/api/mail", header, "{\"to\":\"CoolDude95\",\"subject\":\"tonight\",\"body\":\"lobby after dinner\"}");
    if (std.mem.indexOf(u8, mailed, "\"ok\":true") == null) return error.MailFailed;
    const report = ops.run(std.heap.page_allocator, .{ .probe = false, .config = false, .live = false, .files = true, .expect_signon = false, .expect_listen = false });
    if (report.fail_n != 0) {
        var text_buf: [8000]u8 = undefined;
        const n = ops.format(&text_buf, &report);
        std.debug.print("{s}\n", .{text_buf[0..n]});
        return error.CheckFailed;
    }
    std.debug.print("SELF-TEST OK\n", .{});
}

fn checkMain() !void {
    const chain = @import("chain.zig");
    const modules = @import("modules.zig");
    chain.applyEnv();
    modules.load();
    chain.attach();
    const report = ops.run(std.heap.page_allocator, .{ .probe = true, .config = true, .live = true, .files = true, .expect_signon = false, .expect_listen = false });
    var text_buf: [16000]u8 = undefined;
    const n = ops.format(&text_buf, &report);
    std.debug.print("{s}", .{text_buf[0..n]});
    if (report.fail_n > 0) std.process.exit(1);
}

fn serveLoop(store: *Store) void {
    const addr = compat.net.Address.parseIp4("0.0.0.0", 8080) catch return;
    var server = addr.listen(.{ .reuse_address = true }) catch return;
    while (true) {
        const conn = server.accept() catch continue;
        const thread = std.Thread.spawn(.{}, serveClient, .{ store, conn }) catch continue;
        thread.detach();
    }
}

fn console() void {
    const in = compat.File{ .inner = std.Io.File.stdin() };
    var buf: [180]u8 = undefined;
    std.debug.print("Thimble host\n", .{});
    std.debug.print("  sign-on   http://0.0.0.0:8080\n", .{});
    std.debug.print("  pool      3333 sha256d  3334 scrypt  3335 ethash  3336 kawpow  3337 randomx  3338 yescrypt\n", .{});
    std.debug.print("  config    host.cfg (environment overrides it)   modules pools.cfg\n", .{});
    while (true) {
        std.debug.print("\n1 report   2 check this host   3 settings   4 quit\n> ", .{});
        const n = in.read(&buf) catch return;
        if (n == 0) return;
        const line = std.mem.trim(u8, buf[0..n], " \r\n");
        if (line.len == 0 or line[0] == '1') {
            const text = pool.reportText(std.heap.page_allocator) catch {
                std.debug.print("report is not ready\n", .{});
                continue;
            };
            std.debug.print("{s}\n", .{text});
        } else if (line[0] == '2') {
            const report = ops.run(std.heap.page_allocator, .{ .probe = true, .config = true, .live = true, .files = true, .expect_signon = true, .expect_listen = true });
            var text_buf: [16000]u8 = undefined;
            const wrote = ops.format(&text_buf, &report);
            std.debug.print("{s}", .{text_buf[0..wrote]});
        } else if (line[0] == '3') {
            settingsMenu(in, &buf);
        } else if (line[0] == '4') {
            std.process.exit(0);
        }
    }
}

fn settingsMenu(in: compat.File, buf: []u8) void {
    std.debug.print("\nSettings. Same fields as the Windows host.\n", .{});
    std.debug.print("  admin    {d} characters in host.cfg\n", .{compat.adminText().len});
    std.debug.print("  pay      {s} sats\n", .{if (compat.payText().len > 0) compat.payText() else "100000"});
    std.debug.print("  upstream {s}\n", .{if (compat.upstreamText().len > 0) compat.upstreamText() else "(none)"});
    std.debug.print("  rpc      {s}\n", .{if (compat.rpcText().len > 0) compat.rpcText() else "(none)"});
    const raw = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, "pools.cfg", 1 << 16) catch "";
    if (raw.len == 0) {
        std.debug.print("  modules  none yet. Ports stay closed.\n", .{});
    } else std.debug.print("  modules\n{s}\n", .{raw});
    std.debug.print("a admin token   b pay sats   c upstream   d rpc   e wallet   f add module   g back\n> ", .{});
    const n = in.read(buf) catch return;
    const pick = std.mem.trim(u8, buf[0..n], " \r\n");
    if (pick.len == 0 or pick[0] == 'g') return;
    const choice = pick[0];
    if (choice == 'f') {
        std.debug.print("name: ", .{});
        const name = std.mem.trim(u8, buf[0 .. in.read(buf) catch return], " \r\n");
        if (name.len == 0 or name.len > 32) {
            std.debug.print("refused. name is required, 32 characters or fewer.\n", .{});
            return;
        }
        var name_buf: [32]u8 = undefined;
        @memcpy(name_buf[0..name.len], name);
        std.debug.print("algorithm (sha256d or scrypt): ", .{});
        const algo = std.mem.trim(u8, buf[0 .. in.read(buf) catch return], " \r\n");
        if (!std.mem.eql(u8, algo, "sha256d") and !std.mem.eql(u8, algo, "scrypt")) {
            std.debug.print("refused. only sha256d and scrypt are checked.\n", .{});
            return;
        }
        var algo_buf: [8]u8 = undefined;
        @memcpy(algo_buf[0..algo.len], algo);
        std.debug.print("port: ", .{});
        const port_s = std.mem.trim(u8, buf[0 .. in.read(buf) catch return], " \r\n");
        const port = std.fmt.parseInt(u16, port_s, 10) catch 0;
        if (port < 1024) {
            std.debug.print("refused. port must be 1024 or higher.\n", .{});
            return;
        }
        std.debug.print("source (host:port or http://user:pass@127.0.0.1:8332), or blank: ", .{});
        const source = std.mem.trim(u8, buf[0 .. in.read(buf) catch return], " \r\n");
        var source_buf: [96]u8 = undefined;
        const sn = @min(source.len, source_buf.len);
        @memcpy(source_buf[0..sn], source[0..sn]);
        std.debug.print("wallet address, or blank: ", .{});
        const wallet = std.mem.trim(u8, buf[0 .. in.read(buf) catch return], " \r\n");
        var wallet_buf: [64]u8 = undefined;
        const wn = @min(wallet.len, wallet_buf.len);
        @memcpy(wallet_buf[0..wn], wallet[0..wn]);
        const previous = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, "pools.cfg", 1 << 16) catch "";
        var file = compat.fs.cwd().createFile("pools.cfg", .{}) catch {
            std.debug.print("could not open pools.cfg\n", .{});
            return;
        };
        if (previous.len > 0) file.writeAll(previous) catch {};
        if (previous.len > 0 and previous[previous.len - 1] != '\n') file.writeAll("\n") catch {};
        file.print("{s}\t{s}\t{d}\t0\tnone\t0\t{s}\t{s}\n", .{ name_buf[0..name.len], algo_buf[0..algo.len], port, source_buf[0..sn], wallet_buf[0..wn] }) catch {};
        file.close();
        std.debug.print("Module saved, off. Turn it on in pools.cfg (the on column) and restart. The port stays closed until the source serves a template.\n", .{});
        return;
    }
    std.debug.print("new value: ", .{});
    const value = std.mem.trim(u8, buf[0 .. in.read(buf) catch return], " \r\n");
    if (choice == 'a') {
        if (value.len < 8) {
            std.debug.print("refused. 8 or more characters.\n", .{});
            return;
        }
        compat.writeHost(value, compat.payText(), compat.rpcText(), compat.upstreamText(), compat.walletText());
    } else if (choice == 'b') {
        if ((std.fmt.parseInt(u64, value, 10) catch 0) == 0) {
            std.debug.print("refused. a positive number of satoshis.\n", .{});
            return;
        }
        compat.writeHost(compat.adminText(), value, compat.rpcText(), compat.upstreamText(), compat.walletText());
    } else if (choice == 'c') {
        compat.writeHost(compat.adminText(), if (compat.payText().len > 0) compat.payText() else "100000", compat.rpcText(), value, compat.walletText());
    } else if (choice == 'd') {
        compat.writeHost(compat.adminText(), if (compat.payText().len > 0) compat.payText() else "100000", value, compat.upstreamText(), compat.walletText());
    } else if (choice == 'e') {
        compat.writeHost(compat.adminText(), if (compat.payText().len > 0) compat.payText() else "100000", compat.rpcText(), compat.upstreamText(), value);
    } else return;
    std.debug.print("Saved host.cfg. Restart the host if a pool is already attached.\n", .{});
}

pub fn main(init: std.process.Init) !void {
    compat.bind(init);
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();
    var check = false;
    var selftest_flag = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--selftest")) selftest_flag = true;
        if (std.mem.eql(u8, arg, "--check")) check = true;
        if (std.mem.eql(u8, arg, "--setup")) compat.force_setup = true;
    }
    if (selftest_flag) {
        compat.loadHostFile();
        return selftest();
    }
    if (check) {
        compat.loadHostFile();
        return checkMain();
    }
    if (compat.force_setup and comptime @import("builtin").os.tag != .windows) compat.promptSetup();
    compat.ensureHost();
    var store = Store.init(std.heap.page_allocator, "thimble.db");
    try store.load();
    pool.pool = pool.Pool.init(std.heap.page_allocator);
    const pool_thread = try std.Thread.spawn(.{}, pool.start, .{});
    pool_thread.detach();
    const http_thread = try std.Thread.spawn(.{}, serveLoop, .{&store});
    http_thread.detach();
    std.debug.print("Thimble host  http://0.0.0.0:8080\n", .{});
    std.debug.print("Pool  3333 sha256d  3334 scrypt  3335 ethash  3336 kawpow  3337 randomx  3338 yescrypt\n", .{});
    std.debug.print("Check  ./thimble --check    live  http://127.0.0.1:8080/api/doctor\n", .{});
    std.debug.print("Admin  http://127.0.0.1:8080/admin   token is in host.cfg, or THIMBLE_ADMIN\n", .{});
    std.debug.print("Files  thimble.db  party.db  host.cfg  pools.cfg  coin.cfg\n", .{});
    if (comptime @import("builtin").os.tag == .windows) {
        @import("server_ui.zig").open();
    } else console();
}
