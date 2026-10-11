const compat = @import("compat.zig");
const std = @import("std");

const HWND = *opaque {};
const HINSTANCE = *opaque {};
const HMENU = *opaque {};
const HICON = *opaque {};
const HCURSOR = *opaque {};
const HBRUSH = *opaque {};
const LPARAM = isize;
const WPARAM = usize;
const LRESULT = isize;
const BOOL = i32;

const WNDCLASSA = extern struct {
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: HINSTANCE,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?[*:0]const u8 = null,
    lpszClassName: [*:0]const u8,
};
const MSG = extern struct { hwnd: ?HWND, message: u32, wParam: WPARAM, lParam: LPARAM, time: u32, pt: extern struct { x: i32, y: i32 } };

extern "user32" fn RegisterClassA(wnd: *const WNDCLASSA) callconv(.winapi) u16;
extern "user32" fn CreateWindowExA(ex: u32, class: [*:0]const u8, title: [*:0]const u8, style: u32, x: i32, y: i32, w: i32, h: i32, parent: ?HWND, menu: ?HMENU, inst: HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?HWND;
extern "user32" fn ShowWindow(hwnd: HWND, cmd: i32) callconv(.winapi) BOOL;
extern "user32" fn MessageBoxA(hwnd: ?HWND, text: [*:0]const u8, title: [*:0]const u8, kind: u32) callconv(.winapi) i32;
extern "user32" fn GetMessageA(msg: *MSG, hwnd: ?HWND, min: u32, max: u32) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageA(msg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn DefWindowProcA(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn PostQuitMessage(code: i32) callconv(.winapi) void;
extern "user32" fn PostMessageA(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) BOOL;
extern "user32" fn SetWindowTextA(hwnd: HWND, text: [*:0]const u8) callconv(.winapi) BOOL;
extern "user32" fn GetWindowTextA(hwnd: HWND, buf: [*]u8, max: i32) callconv(.winapi) i32;
extern "user32" fn SendMessageA(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn MoveWindow(hwnd: HWND, x: i32, y: i32, w: i32, h: i32, repaint: BOOL) callconv(.winapi) BOOL;
extern "user32" fn LoadCursorA(inst: ?HINSTANCE, name: usize) callconv(.winapi) ?HCURSOR;
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
extern "user32" fn GetClientRect(hwnd: HWND, rect: *RECT) callconv(.winapi) BOOL;
extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(.winapi) HINSTANCE;
extern "kernel32" fn CreateThread(attr: ?*anyopaque, stack: usize, start: *const fn (?*anyopaque) callconv(.winapi) u32, param: ?*anyopaque, flags: u32, id: ?*u32) callconv(.winapi) ?*anyopaque;

const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_BORDER: u32 = 0x00800000;
const WS_VSCROLL: u32 = 0x00200000;
const ES_PASSWORD: u32 = 0x0020;
const ES_AUTOHSCROLL: u32 = 0x0080;
const CBS_DROPDOWNLIST: u32 = 0x0003;
const BS_DEFPUSHBUTTON: u32 = 0x0001;
const LBS_NOTIFY: u32 = 0x0001;
const LBS_NOINTEGRALHEIGHT: u32 = 0x0100;
const WM_DESTROY: u32 = 0x0002;
const WM_SIZE: u32 = 0x0005;
const WM_COMMAND: u32 = 0x0111;
const WM_KEYDOWN: u32 = 0x0100;
const WM_CREATE: u32 = 0x0001;
const WM_NET: u32 = 0x8000 + 1;
const CB_ADDSTRING: u32 = 0x0143;
const CB_SETCURSEL: u32 = 0x014E;
const CB_GETCURSEL: u32 = 0x0147;
const LB_ADDSTRING: u32 = 0x0180;
const LB_RESETCONTENT: u32 = 0x0184;
const LB_GETCURSEL: u32 = 0x0188;
const LB_GETCOUNT: u32 = 0x018B;
const LB_SETTOPINDEX: u32 = 0x0197;
const VK_RETURN: WPARAM = 13;
const SW_SHOW: i32 = 5;
const SW_HIDE: i32 = 0;
const IDC_ARROW: usize = 32512;

const rooms = [_][:0]const u8{ "Lobby", "Thirtysomething", "Computer Help", "Sports Bar", "New Member Lounge" };

var hwnd: HWND = undefined;
var host_box: HWND = undefined;
var port_box: HWND = undefined;
var name_box: HWND = undefined;
var pass_box: HWND = undefined;
var room_box: HWND = undefined;
var signup_btn: HWND = undefined;
var sign_btn: HWND = undefined;
var log_box: HWND = undefined;
var input_box: HWND = undefined;
var send_btn: HWND = undefined;
var rooms_box: HWND = undefined;
var mail_btn: HWND = undefined;
var mine_btn: HWND = undefined;
var worker_box: HWND = undefined;
var status_box: HWND = undefined;
var screen_name: [32]u8 = undefined;
var token: [80]u8 = undefined;
var host_text: [80]u8 = undefined;
var port_n: u16 = 8080;
var room_i: usize = 0;
var since: u32 = 0;
var online: bool = false;

fn textOf(control: HWND, buf: []u8) []u8 {
    const n = GetWindowTextA(control, buf.ptr, @intCast(buf.len));
    return buf[0..@intCast(n)];
}

fn field(body: []const u8, key: []const u8, out: []u8) []u8 {
    var pat: [40]u8 = undefined;
    const p = std.fmt.bufPrint(&pat, "\"{s}\":\"", .{key}) catch return out[0..0];
    const at = std.mem.indexOf(u8, body, p) orelse return out[0..0];
    var i = at + p.len;
    var n: usize = 0;
    while (i < body.len and body[i] != '"' and n + 1 < out.len) : (i += 1) {
        if (body[i] == '\\' and i + 1 < body.len) i += 1;
        out[n] = body[i];
        n += 1;
    }
    return out[0..n];
}

fn http(method: []const u8, path: []const u8, body: []const u8, bearer: []const u8, out: []u8) ?[]u8 {
    // The Windows build talks to the Zig host with WinHTTP. Linked below.
    return winhttp(method, path, body, bearer, out);
}

extern "winhttp" fn WinHttpOpen(agent: [*:0]const u16, access: u32, proxy: ?*anyopaque, bypass: ?*anyopaque, flags: u32) callconv(.winapi) ?*anyopaque;
extern "winhttp" fn WinHttpConnect(session: ?*anyopaque, host: [*:0]const u16, port: u16, reserved: u32) callconv(.winapi) ?*anyopaque;
extern "winhttp" fn WinHttpOpenRequest(conn: ?*anyopaque, verb: [*:0]const u16, path: [*:0]const u16, version: ?*anyopaque, referrer: ?*anyopaque, accept: ?*anyopaque, flags: u32) callconv(.winapi) ?*anyopaque;
extern "winhttp" fn WinHttpSendRequest(req: ?*anyopaque, headers: [*:0]const u16, headers_len: u32, optional: ?*anyopaque, optional_len: u32, total: u32, context: usize) callconv(.winapi) BOOL;
extern "winhttp" fn WinHttpReceiveResponse(req: ?*anyopaque, reserved: ?*anyopaque) callconv(.winapi) BOOL;
extern "winhttp" fn WinHttpReadData(req: ?*anyopaque, buf: [*]u8, len: u32, read: *u32) callconv(.winapi) BOOL;
extern "winhttp" fn WinHttpCloseHandle(handle: ?*anyopaque) callconv(.winapi) BOOL;

fn toWide(src: []const u8, out: []u16) [*:0]u16 {
    var i: usize = 0;
    while (i < src.len and i + 1 < out.len) : (i += 1) out[i] = src[i];
    out[i] = 0;
    return @ptrCast(out.ptr);
}

fn winhttp(method: []const u8, path: []const u8, body: []const u8, bearer: []const u8, out: []u8) ?[]u8 {
    var host_w: [80]u16 = undefined;
    var verb_w: [12]u16 = undefined;
    var path_w: [180]u16 = undefined;
    var hdr_w: [220]u16 = undefined;
    const session = WinHttpOpen(toWide("Thimble/5.0", &host_w), 0, null, null, 0) orelse return null;
    defer _ = WinHttpCloseHandle(session);
    const conn = WinHttpConnect(session, toWide(std.mem.sliceTo(&host_text, 0), &verb_w), port_n, 0) orelse return null;
    defer _ = WinHttpCloseHandle(conn);
    const req = WinHttpOpenRequest(conn, toWide(method, &path_w), toWide(path, &hdr_w), null, null, null, 0) orelse return null;
    defer _ = WinHttpCloseHandle(req);
    var header_buf: [220]u8 = undefined;
    const header = std.fmt.bufPrintSentinel(&header_buf, "Content-Type: application/json\r\nAuthorization: Bearer {s}\r\n", .{bearer}, 0) catch return null;
    var header_w: [240]u16 = undefined;
    const sent = WinHttpSendRequest(req, toWide(header, &header_w), 0xFFFFFFFF, if (body.len == 0) null else @ptrCast(@constCast(body.ptr)), @intCast(body.len), @intCast(body.len), 0);
    if (sent == 0 or WinHttpReceiveResponse(req, null) == 0) return null;
    var n: usize = 0;
    while (n + 1 < out.len) {
        var got: u32 = 0;
        if (WinHttpReadData(req, out.ptr + n, @intCast(out.len - 1 - n), &got) == 0 or got == 0) break;
        n += got;
    }
    return out[0..n];
}

fn addLine(text: []const u8) void {
    const copy = std.heap.page_allocator.dupeSentinel(u8, text, 0) catch return;
    _ = PostMessageA(hwnd, WM_NET, 0, @bitCast(@intFromPtr(copy.ptr)));
}

fn pollThread(_: ?*anyopaque) callconv(.winapi) u32 {
    var path_buf: [160]u8 = undefined;
    var raw: [16000]u8 = undefined;
    while (online) {
        const room = rooms[room_i];
        const path = std.fmt.bufPrint(&path_buf, "/api/messages?room={s}&since={d}", .{ room, since }) catch continue;
        var spaced: [160]u8 = undefined;
        for (path, 0..) |c, i| spaced[i] = if (c == ' ') '+' else c;
        if (winhttp("GET", spaced[0..path.len], "", std.mem.sliceTo(&token, 0), &raw)) |body| {
            var rest = body;
            while (std.mem.indexOf(u8, rest, "\"id\":")) |at| {
                const id = std.fmt.parseInt(u32, rest[at + 5 ..], 10) catch 0;
                var name_out: [40]u8 = undefined;
                var body_out: [300]u8 = undefined;
                const name = field(rest[at..], "name", &name_out);
                const text = field(rest[at..], "body", &body_out);
                if (id > since and name.len > 0) {
                    since = id;
                    var shown: [360]u8 = undefined;
                    const line = std.fmt.bufPrint(&shown, "{s}:  {s}", .{ name, text }) catch text;
                    addLine(line);
                }
                rest = rest[at + 5 ..];
            }
        }
        compat.time.sleep(2 * std.time.ns_per_s);
    }
    return 0;
}

fn sign(kind: []const u8) void {
    var name_raw: [32]u8 = undefined;
    var pass_raw: [64]u8 = undefined;
    var host_raw: [80]u8 = undefined;
    var port_raw: [8]u8 = undefined;
    const name = textOf(name_box, &name_raw);
    const pass = textOf(pass_box, &pass_raw);
    const host = textOf(host_box, &host_raw);
    const port = textOf(port_box, &port_raw);
    @memset(&host_text, 0);
    @memcpy(host_text[0..host.len], host);
    port_n = std.fmt.parseInt(u16, port, 10) catch 8080;
    var body_buf: [220]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"screenName\":\"{s}\",\"password\":\"{s}\"}}", .{ name, pass }) catch return;
    var raw: [800]u8 = undefined;
    const path = if (std.mem.eql(u8, kind, "signup")) "/api/signup" else "/api/login";
    const response = http("POST", path, body, "", &raw) orelse {
        var msg: [120]u8 = undefined;
        const line = std.fmt.bufPrintSentinel(&msg, "Host did not answer at {s}:{s}.", .{ host, port }, 0) catch return;
        _ = MessageBoxA(hwnd, line, "Thimble", 0);
        return;
    };
    if (std.mem.indexOf(u8, response, "\"ok\":true") == null) {
        var err: [180]u8 = undefined;
        const message = field(response, "error", &err);
        var z: [181]u8 = undefined;
        @memcpy(z[0..message.len], message);
        z[message.len] = 0;
        _ = MessageBoxA(hwnd, z[0..message.len :0], "Thimble", 0);
        return;
    }
    @memset(&token, 0);
    @memset(&screen_name, 0);
    const tok = field(response, "token", &token);
    _ = tok;
    const signed_name = field(response, "screenName", &screen_name);
    _ = signed_name;
    room_i = @intCast(SendMessageA(room_box, CB_GETCURSEL, 0, 0));
    if (room_i > 4) room_i = 0;
    since = 0;
    online = true;
    var remember: [96]u8 = undefined;
    if (std.fmt.bufPrint(&remember, "{s}\n{s}\n", .{ host, port })) |saved| {
        var file = compat.fs.cwd().createFile("client.cfg", .{}) catch null;
        if (file) |*f| {
            f.writeAll(saved) catch {};
            f.close();
        }
    } else |_| {}
    _ = SendMessageA(log_box, LB_RESETCONTENT, 0, 0);
    showChat(true);
    _ = CreateThread(null, 0, pollThread, null, 0, null);
}

fn showChat(on: bool) void {
    const sign_show: i32 = if (on) SW_HIDE else SW_SHOW;
    const chat_show: i32 = if (on) SW_SHOW else SW_HIDE;
    _ = ShowWindow(host_box, sign_show);
    _ = ShowWindow(port_box, sign_show);
    _ = ShowWindow(name_box, sign_show);
    _ = ShowWindow(pass_box, sign_show);
    _ = ShowWindow(room_box, sign_show);
    _ = ShowWindow(signup_btn, sign_show);
    _ = ShowWindow(sign_btn, sign_show);
    _ = ShowWindow(log_box, chat_show);
    _ = ShowWindow(input_box, chat_show);
    _ = ShowWindow(send_btn, chat_show);
    _ = ShowWindow(rooms_box, chat_show);
    _ = ShowWindow(mail_btn, chat_show);
    _ = ShowWindow(mine_btn, chat_show);
    _ = ShowWindow(worker_box, chat_show);
    _ = SetWindowTextA(hwnd, if (on) "Thimble - People Connection" else "Thimble - Sign On");
}

fn sendChat() void {
    if (!online) return;
    var text_raw: [240]u8 = undefined;
    const text = textOf(input_box, &text_raw);
    if (text.len == 0) return;
    _ = SetWindowTextA(input_box, "");
    var body_buf: [520]u8 = undefined;
    const body = std.fmt.bufPrint(&body_buf, "{{\"room\":\"{s}\",\"text\":\"{s}\"}}", .{ rooms[room_i], text }) catch return;
    var raw: [200]u8 = undefined;
    _ = http("POST", "/api/messages", body, std.mem.sliceTo(&token, 0), &raw);
}

fn startRig() void {
    var worker_raw: [64]u8 = undefined;
    const worker = textOf(worker_box, &worker_raw);
    var host_raw: [80]u8 = undefined;
    var port_raw: [8]u8 = undefined;
    const host = textOf(host_box, &host_raw);
    const port = textOf(port_box, &port_raw);
    @memset(&host_text, 0);
    @memcpy(host_text[0..host.len], host);
    port_n = std.fmt.parseInt(u16, port, 10) catch 3333;
    const addr = compat.net.Address.parseIp4(std.mem.sliceTo(&host_text, 0), port_n) catch return;
    const stream = compat.net.tcpConnectToAddress(addr) catch {
        var msg: [120]u8 = undefined;
        const line = std.fmt.bufPrintSentinel(&msg, "Pool did not answer at {s}:{s}.", .{ host, port }, 0) catch return;
        _ = MessageBoxA(hwnd, line, "Thimble", 0);
        return;
    };
    var login: [220]u8 = undefined;
    const sub = std.fmt.bufPrint(&login, "{{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"Thimble\"]}}\n", .{}) catch return;
    _ = stream.writeAll(sub) catch return;
    const auth = std.fmt.bufPrint(&login, "{{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"{s}\",\"gpu\"]}}\n", .{worker}) catch return;
    _ = stream.writeAll(auth) catch return;
    addLine("Rig authorized on the pool.");
}

fn readMail() void {
    var raw: [8000]u8 = undefined;
    const body = http("GET", "/api/mail", "", std.mem.sliceTo(&token, 0), &raw) orelse return;
    addLine("--- Mail ---");
    var rest = body;
    var any = false;
    while (std.mem.indexOf(u8, rest, "\"subject\":\"")) |at| {
        var subject: [80]u8 = undefined;
        var sender: [40]u8 = undefined;
        var text: [240]u8 = undefined;
        var shown: [400]u8 = undefined;
        const line = std.fmt.bufPrint(&shown, "Mail from {s}: {s} — {s}", .{ field(rest[at..], "sender", &sender), field(rest[at..], "subject", &subject), field(rest[at..], "body", &text) }) catch continue;
        addLine(line);
        any = true;
        rest = rest[at + 11 ..];
    }
    if (!any) addLine("No mail.");
}

fn layout() void {
    var rect = RECT{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    _ = GetClientRect(hwnd, &rect);
    const w = rect.right;
    const h = rect.bottom;
    _ = MoveWindow(host_box, 24, 56, 180, 22, 1);
    _ = MoveWindow(port_box, 212, 56, 70, 22, 1);
    _ = MoveWindow(name_box, 24, 104, 260, 22, 1);
    _ = MoveWindow(pass_box, 24, 150, 260, 22, 1);
    _ = MoveWindow(room_box, 24, 196, 260, 120, 1);
    _ = MoveWindow(signup_btn, 24, 236, 100, 28, 1);
    _ = MoveWindow(sign_btn, 136, 236, 100, 28, 1);
    _ = MoveWindow(rooms_box, 8, 8, 160, h - 64, 1);
    _ = MoveWindow(log_box, 176, 8, w - 184, h - 92, 1);
    _ = MoveWindow(input_box, 176, h - 76, w - 280, 22, 1);
    _ = MoveWindow(send_btn, w - 96, h - 78, 80, 26, 1);
    _ = MoveWindow(mail_btn, 8, h - 48, 160, 24, 1);
    _ = MoveWindow(worker_box, 176, h - 46, 140, 18, 1);
    _ = MoveWindow(mine_btn, 324, h - 48, 90, 24, 1);
    _ = MoveWindow(status_box, 420, h - 46, w - 430, 18, 1);
}

fn child(class: [*:0]const u8, title: [*:0]const u8, style: u32, id: usize) HWND {
    return CreateWindowExA(0, class, title, style, 0, 0, 10, 10, hwnd, @ptrFromInt(id), GetModuleHandleA(null), null).?;
}

fn wndProc(window: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT {
    hwnd = window;
    switch (msg) {
        WM_CREATE => {
            _ = child("STATIC", "thimble", WS_CHILD | WS_VISIBLE, 1);
            host_box = child("EDIT", "127.0.0.1", WS_CHILD | WS_VISIBLE | WS_BORDER, 2);
            port_box = child("EDIT", "8080", WS_CHILD | WS_VISIBLE | WS_BORDER, 3);
            name_box = child("EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER, 4);
            pass_box = child("EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_PASSWORD, 5);
            room_box = child("COMBOBOX", "", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 6);
            signup_btn = child("BUTTON", "Sign Up", WS_CHILD | WS_VISIBLE, 7);
            sign_btn = child("BUTTON", "Sign On", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON, 8);
            rooms_box = child("LISTBOX", "", WS_CHILD | WS_BORDER | LBS_NOTIFY, 9);
            log_box = child("LISTBOX", "", WS_CHILD | WS_BORDER | WS_VSCROLL | LBS_NOINTEGRALHEIGHT, 10);
            input_box = child("EDIT", "", WS_CHILD | WS_BORDER | ES_AUTOHSCROLL, 11);
            send_btn = child("BUTTON", "Send", WS_CHILD, 12);
            mail_btn = child("BUTTON", "You've Got Mail", WS_CHILD, 13);
            mine_btn = child("BUTTON", "Start rig", WS_CHILD, 15);
            worker_box = child("EDIT", "Kitchen.rig1", WS_CHILD | WS_BORDER, 16);
            status_box = child("STATIC", "Offline. Run the server EXE, then sign up.", WS_CHILD | WS_VISIBLE, 14);
            for (rooms) |room| {
                _ = SendMessageA(room_box, CB_ADDSTRING, 0, @bitCast(@intFromPtr(room.ptr)));
                _ = SendMessageA(rooms_box, LB_ADDSTRING, 0, @bitCast(@intFromPtr(room.ptr)));
            }
            _ = SendMessageA(room_box, CB_SETCURSEL, 0, 0);
            layout();
            return 0;
        },
        WM_SIZE => {
            layout();
            return 0;
        },
        WM_COMMAND => {
            const id: usize = wp & 0xffff;
            if (id == 7) sign("signup");
            if (id == 8) sign("login");
            if (id == 12) sendChat();
            if (id == 13 and online) readMail();
            if (id == 15 and online) startRig();
            if ((wp >> 16) == 2 and id == 9 and online) {
                const picked = SendMessageA(rooms_box, LB_GETCURSEL, 0, 0);
                if (picked >= 0 and picked < 5) {
                    room_i = @intCast(picked);
                    since = 0;
                    _ = SendMessageA(log_box, LB_RESETCONTENT, 0, 0);
                    addLine("You have entered the room.");
                }
            }
            return 0;
        },
        WM_NET => {
            const line: [*:0]const u8 = @ptrFromInt(@as(usize, @bitCast(lp)));
            _ = SendMessageA(log_box, LB_ADDSTRING, 0, lp);
            const count = SendMessageA(log_box, LB_GETCOUNT, 0, 0);
            _ = SendMessageA(log_box, LB_SETTOPINDEX, @intCast(count - 1), 0);
            std.heap.page_allocator.free(std.mem.span(line));
            return 0;
        },
        WM_KEYDOWN => if (wp == VK_RETURN and online) sendChat(),
        WM_DESTROY => {
            online = false;
            PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return DefWindowProcA(window, msg, wp, lp);
}

pub fn main(init: std.process.Init) void {
    compat.bind(init);
    const inst = GetModuleHandleA(null);
    const class = WNDCLASSA{
        .lpfnWndProc = wndProc,
        .hInstance = inst,
        .hCursor = LoadCursorA(null, IDC_ARROW),
        .hbrBackground = @ptrFromInt(16),
        .lpszClassName = "ThimbleZig",
    };
    _ = RegisterClassA(&class);
    hwnd = CreateWindowExA(0, "Thimble Zig", "Thimble — Sign On", WS_OVERLAPPEDWINDOW, 80, 80, 760, 480, null, null, inst, null).?;
    _ = ShowWindow(hwnd, SW_SHOW);
    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) != 0) {
        if (msg.message == WM_KEYDOWN and msg.wParam == VK_RETURN and online) sendChat();
        _ = TranslateMessage(&msg);
        _ = DispatchMessageA(&msg);
    }
}
