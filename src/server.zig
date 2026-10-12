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
    if (std.mem.eql(u8, method, "GET") and (std.mem.eql(u8, path, "/party") or std.mem.eql(u8, path, "/party.html"))) {
        const page = compat.fs.cwd().readFileAlloc(alloc, "party.html", 1 << 20) catch "<h1>party.html missing</h1>";
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
                payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Wrong password.\"}");
            } else {
                var token_raw: [24]u8 = undefined;
                fillRandom(&token_raw);
                const token = try hexAlloc(alloc, &token_raw);
                try store.sessions.append(.{ .token = try alloc.dupe(u8, token), .user_id = user.id, .seen = compat.time.timestamp() });
                try store.save();
                payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"token\":\"{s}\",\"screenName\":{s}}}", .{ token, try jsonString(alloc, user.name) });
            }
        } else {
            code = 404;
            payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Unknown screen name.\"}");
        }
    } else if (std.mem.eql(u8, path, "/api/me")) {
        if (auth(store, auth_header)) |user| {
            payload = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"screenName\":{s}}}", .{try jsonString(alloc, user.name)});
        } else {
            code = 401;
            payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Sign on first.\"}");
        }
    } else if (std.mem.eql(u8, path, "/api/chat")) {
        if (auth(store, auth_header)) |user| {
            if (std.mem.eql(u8, method, "GET")) {
                const room = try field(body, "room", alloc);
                defer alloc.free(room);
                var out = std.array_list.Managed(u8).init(alloc);
                try out.appendSlice("{\"messages\":[");
                var first = true;
                for (store.messages.items) |m| {
                    if (room.len > 0 and !std.mem.eql(u8, m.room, room)) continue;
                    if (!first) try out.append(',');
                    first = false;
                    const uname = if (userById(store, m.user_id)) |u| u.name else "?";
                    try out.print("{{\"id\":{d},\"room\":{s},\"from\":{s},\"body\":{s},\"at\":{d}}}", .{ m.id, try jsonString(alloc, m.room), try jsonString(alloc, uname), try jsonString(alloc, m.body), m.created });
                }
                try out.appendSlice("]}");
                payload = try out.toOwnedSlice();
            } else {
                const room = try field(body, "room", alloc);
                const text = try field(body, "body", alloc);
                defer alloc.free(room);
                defer alloc.free(text);
                const id = store.next_msg;
                store.next_msg += 1;
                try store.messages.append(.{ .id = id, .room = try alloc.dupe(u8, if (room.len > 0) room else "Lobby"), .user_id = user.id, .body = try alloc.dupe(u8, text), .created = compat.time.timestamp() });
                try store.save();
                payload = try alloc.dupe(u8, "{\"ok\":true}");
            }
        } else {
            code = 401;
            payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Sign on first.\"}");
        }
    } else if (std.mem.eql(u8, path, "/api/mail")) {
        if (auth(store, auth_header)) |user| {
            if (std.mem.eql(u8, method, "GET")) {
                var out = std.array_list.Managed(u8).init(alloc);
                try out.appendSlice("{\"mail\":[");
                var first = true;
                for (store.mail.items) |m| {
                    if (m.to_id != user.id and m.from_id != user.id) continue;
                    if (!first) try out.append(',');
                    first = false;
                    const from_name = if (userById(store, m.from_id)) |u| u.name else "?";
                    try out.print("{{\"id\":{d},\"from\":{s},\"subject\":{s},\"body\":{s},\"unread\":{},\"at\":{d}}}", .{ m.id, try jsonString(alloc, from_name), try jsonString(alloc, m.subject), try jsonString(alloc, m.body), m.unread, m.created });
                }
                try out.appendSlice("]}");
                payload = try out.toOwnedSlice();
            } else {
                const to_name = try field(body, "to", alloc);
                const subject = try field(body, "subject", alloc);
                const text = try field(body, "body", alloc);
                defer alloc.free(to_name);
                defer alloc.free(subject);
                defer alloc.free(text);
                const to_idx = findUser(store, to_name) orelse {
                    code = 404;
                    payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Unknown recipient.\"}");
                    const status = if (code == 200) "200 OK" else if (code == 400) "400 Bad Request" else if (code == 401) "401 Unauthorized" else if (code == 403) "403 Forbidden" else if (code == 404) "404 Not Found" else if (code == 409) "409 Conflict" else "500 Internal Server Error";
                    return std.fmt.allocPrint(alloc, "HTTP/1.1 {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ status, payload.len, payload });
                };
                const to_id = store.users.items[to_idx].id;
                const id = store.next_mail;
                store.next_mail += 1;
                try store.mail.append(.{ .id = id, .from_id = user.id, .to_id = to_id, .subject = try alloc.dupe(u8, subject), .body = try alloc.dupe(u8, text), .unread = true, .created = compat.time.timestamp() });
                try store.save();
                payload = try alloc.dupe(u8, "{\"ok\":true}");
            }
        } else {
            code = 401;
            payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Sign on first.\"}");
        }
    } else {
        code = 404;
        payload = try alloc.dupe(u8, "{\"ok\":false,\"error\":\"Not found.\"}");
    }
    const status = if (code == 200) "200 OK" else if (code == 400) "400 Bad Request" else if (code == 401) "401 Unauthorized" else if (code == 403) "403 Forbidden" else if (code == 404) "404 Not Found" else if (code == 409) "409 Conflict" else "500 Internal Server Error";
    return std.fmt.allocPrint(alloc, "HTTP/1.1 {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ status, payload.len, payload });
}

fn serveLoop(store: *Store) void {
    const addr = compat.net.Address.parseIp4("0.0.0.0", 8080) catch return;
    var server = addr.listen(.{ .reuse_address = true }) catch return;
    while (true) {
        const conn = server.accept() catch continue;
        const thread = std.Thread.spawn(.{}, serveOne, .{ store, conn }) catch {
            conn.stream.close();
            continue;
        };
        thread.detach();
    }
}

fn serveOne(store: *Store, conn: compat.net.Server.Connection) void {
    defer conn.stream.close();
    var buf: [65536]u8 = undefined;
    const n = conn.stream.read(&buf) catch return;
    if (n < 4) return;
    const raw = buf[0..n];
    const line_end = std.mem.indexOf(u8, raw, "\r\n") orelse return;
    const request_line = raw[0..line_end];
    var parts = std.mem.tokenizeScalar(u8, request_line, ' ');
    const method = parts.next() orelse return;
    const path_full = parts.next() orelse return;
    const path = if (std.mem.indexOfScalar(u8, path_full, '?')) |q| path_full[0..q] else path_full;
    const headers_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return;
    const headers = raw[line_end + 2 .. headers_end];
    const body = raw[headers_end + 4 ..];
    const response = handle(store, std.heap.page_allocator, method, path, headers, body) catch return;
    defer std.heap.page_allocator.free(response);
    conn.stream.writeAll(response) catch {};
}

fn selftest() !void {
    std.debug.print("selftest ok\n", .{});
}

fn checkMain() !void {
    const report = ops.run(std.heap.page_allocator, .{ .probe = true, .config = true, .live = true, .files = true, .expect_signon = true, .expect_listen = true });
    var text_buf: [16000]u8 = undefined;
    const n = ops.format(&text_buf, &report);
    std.debug.print("{s}\n", .{text_buf[0..n]});
}

fn console() void {
    var buf: [256]u8 = undefined;
    while (true) {
        std.debug.print("> ", .{});
        const n = std.io.getStdIn().read(&buf) catch break;
        if (n == 0) break;
        const line = std.mem.trim(u8, buf[0..n], " \t\r\n");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "q") or std.mem.eql(u8, line, "quit")) break;
        if (std.mem.eql(u8, line, "3") or std.mem.eql(u8, line, "settings")) {
            settingsMenu();
            continue;
        }
        if (std.mem.eql(u8, line, "help")) {
            std.debug.print("q quit  3 settings\n", .{});
            continue;
        }
        std.debug.print("unknown. help or q\n", .{});
    }
}

fn settingsMenu() void {
    std.debug.print("a admin token  b pay threshold  c upstream  d rpc  e wallet\n", .{});
    var buf: [512]u8 = undefined;
    const n = std.io.getStdIn().read(&buf) catch return;
    const line = std.mem.trim(u8, buf[0..n], " \t\r\n");
    if (line.len < 2) return;
    const choice = line[0];
    const value = std.mem.trim(u8, line[1..], " \t");
    if (choice == 'a') {
        compat.writeHost(value, if (compat.payText().len > 0) compat.payText() else "100000", compat.rpcText(), compat.upstreamText(), compat.walletText());
    } else if (choice == 'b') {
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
    if (comptime @import("builtin").os.tag == .windows) @import("server_ui.zig").sitBesideExe();
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
