const compat = @import("compat.zig");
const std = @import("std");
const HWND = *opaque {};
const HINSTANCE = *opaque {};
const HMENU = *opaque {};
const HBRUSH = *opaque {};
const LRESULT = isize;
const WPARAM = usize;
const LPARAM = isize;
const WNDCLASSA = extern struct {
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: HINSTANCE,
    hIcon: ?*opaque {} = null,
    hCursor: ?*opaque {} = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?[*:0]const u8 = null,
    lpszClassName: [*:0]const u8,
};
const MSG = extern struct { hwnd: ?HWND, message: u32, wParam: WPARAM, lParam: LPARAM, time: u32, pt: extern struct { x: i32, y: i32 } };
extern "user32" fn RegisterClassA(wnd: *const WNDCLASSA) callconv(.winapi) u16;
extern "user32" fn CreateWindowExA(ex: u32, class: [*:0]const u8, title: [*:0]const u8, style: u32, x: i32, y: i32, w: i32, h: i32, parent: ?HWND, menu: ?HMENU, inst: HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?HWND;
extern "user32" fn ShowWindow(hwnd: HWND, cmd: i32) callconv(.winapi) i32;
extern "user32" fn GetMessageA(msg: *MSG, hwnd: ?HWND, min: u32, max: u32) callconv(.winapi) i32;
extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) i32;
extern "user32" fn DispatchMessageA(msg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn DefWindowProcA(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.winapi) i32;
extern "user32" fn PostQuitMessage(code: i32) callconv(.winapi) void;
extern "user32" fn SetWindowTextA(hwnd: HWND, text: [*:0]const u8) callconv(.winapi) i32;
extern "user32" fn GetWindowTextA(hwnd: HWND, buf: [*]u8, max: i32) callconv(.winapi) i32;
extern "user32" fn SendMessageA(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn SetFocus(hwnd: HWND) callconv(.winapi) HWND;
extern "user32" fn CreateMenu() callconv(.winapi) HMENU;
extern "user32" fn CreatePopupMenu() callconv(.winapi) HMENU;
extern "user32" fn AppendMenuA(menu: HMENU, flags: u32, id: usize, text: [*:0]const u8) callconv(.winapi) i32;
extern "user32" fn SetMenu(hwnd: HWND, menu: HMENU) callconv(.winapi) i32;
extern "user32" fn SetTimer(hwnd: HWND, id: usize, ms: u32, proc: ?*anyopaque) callconv(.winapi) usize;
extern "kernel32" fn GetModuleHandleA(name: ?[*:0]const u8) callconv(.winapi) HINSTANCE;
extern "comctl32" fn InitCommonControls() callconv(.winapi) void;
extern "gdi32" fn CreateSolidBrush(color: u32) callconv(.winapi) HBRUSH;
const PBM_SETPOS: u32 = 0x0402;
const PBM_SETRANGE: u32 = 0x0401;

const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_BORDER: u32 = 0x00800000;
const WS_VSCROLL: u32 = 0x00200000;
const ES_AUTOHSCROLL: u32 = 0x0080;
const ES_READONLY: u32 = 0x0800;
const CBS_DROPDOWNLIST: u32 = 0x0003;
const BS_AUTOCHECKBOX: u32 = 0x0003;
const MF_STRING: u32 = 0;
const MF_POPUP: u32 = 0x10;
const CB_ADDSTRING: u32 = 0x0143;
const CB_RESETCONTENT: u32 = 0x014B;
const CB_SETCURSEL: u32 = 0x014E;
const CB_GETCURSEL: u32 = 0x0147;
const LB_ADDSTRING: u32 = 0x0180;
const LB_RESETCONTENT: u32 = 0x0184;
const LB_GETCURSEL: u32 = 0x0188;
const BM_GETCHECK: u32 = 0x00F0;
const BM_SETCHECK: u32 = 0x00F1;
const CBN_SELCHANGE: u32 = 1;
const WM_DESTROY: u32 = 2;
const WM_COMMAND: u32 = 0x0111;
const WM_TIMER: u32 = 0x0113;
const ID_SETTINGS: usize = 101;
const ID_REFRESH: usize = 102;
const ID_EXIT: usize = 103;
const ID_CHECK: usize = 104;

const Coin = struct { name: [:0]const u8, algo: [:0]const u8, port: u16, repo: [:0]const u8, merges: []const [:0]const u8 };
const coins = [_]Coin{
    .{ .name = "Bitcoin", .algo = "sha256d", .port = 3333, .repo = "https://github.com/bitcoin/bitcoin", .merges = &.{ "Namecoin", "Elastos" } },
    .{ .name = "Litecoin", .algo = "scrypt", .port = 3334, .repo = "https://github.com/litecoin-project/litecoin", .merges = &.{ "Dogecoin" } },
    .{ .name = "Monero", .algo = "randomx", .port = 3337, .repo = "https://github.com/monero-project/monero", .merges = &.{ "none" } },
    .{ .name = "Ethereum Classic", .algo = "ethash", .port = 3335, .repo = "https://github.com/etclabscore/core-geth", .merges = &.{ "none" } },
    .{ .name = "Ravencoin", .algo = "kawpow", .port = 3336, .repo = "https://github.com/RavenProject/Ravencoin", .merges = &.{ "none" } },
    .{ .name = "Dogecoin", .algo = "scrypt", .port = 3334, .repo = "https://github.com/dogecoin/dogecoin", .merges = &.{ "Litecoin" } },
    .{ .name = "Yescrypt", .algo = "yescrypt", .port = 3338, .repo = "https://github.com/globaltoken/globaltoken", .merges = &.{ "none" } },
};

const Module = struct { name: [32]u8, name_len: usize, algo: [16]u8, algo_len: usize, port: u16, on: bool, merge: [24]u8, merge_len: usize, bonus: u8, source: [96]u8, source_len: usize, wallet: [64]u8, wallet_len: usize };
var modules: [8]Module = undefined;
var module_count: usize = 0;
var house_on = false;
var keep_all = true;
var configured = false;

var action_line: HWND = undefined;
var progress_bar: HWND = undefined;
var main_hwnd: HWND = undefined;
var settings_hwnd: ?HWND = null;
var repo_box: HWND = undefined;
var coin_box: HWND = undefined;
var merge_box: HWND = undefined;
var merge_check: HWND = undefined;
var bonus_box: HWND = undefined;
var data_box: HWND = undefined;
var house_check: HWND = undefined;
var source_box: HWND = undefined;
var wallet_box: HWND = undefined;
var settings_list: HWND = undefined;
var report_box: HWND = undefined;
var summary: HWND = undefined;
var tunnel_box: HWND = undefined;
var tunnel_line: HWND = undefined;
var tunnel_child: compat.Child = .{ .argv = &.{} };
var tunnel_live = false;
var tunnel_shell: [420]u8 = @splat(0);
var tunnel_cmd = [_][]const u8{ "cmd.exe", "/c", "" };
var mine_box: HWND = undefined;
var mine_line: HWND = undefined;
var mine_child: compat.Child = .{ .argv = &.{} };
var mine_live = false;
var mine_shell: [320]u8 = @splat(0);
var mine_argv = [_][]const u8{ "cmd.exe", "/c", "" };
var brush: HBRUSH = undefined;
var check_busy = false;
var check_ready = false;
var check_hold = false;
var check_buf: [16000]u8 = @splat(0);
var check_len: usize = 0;

fn child(parent: HWND, class: [*:0]const u8, title: [*:0]const u8, style: u32, x: i32, y: i32, w: i32, h: i32, id: usize) HWND {
    return CreateWindowExA(0, class, title, style, x, y, w, h, parent, @ptrFromInt(id), GetModuleHandleA(null), null).?;
}
fn textOf(control: HWND, buf: []u8) []u8 {
    const n = GetWindowTextA(control, buf.ptr, @intCast(buf.len));
    return buf[0..@intCast(n)];
}
fn setText(control: HWND, text: []const u8) void {
    var z: [240]u8 = undefined;
    const n = @min(text.len, z.len - 1);
    @memcpy(z[0..n], text[0..n]);
    z[n] = 0;
    _ = SetWindowTextA(control, z[0..n :0]);
}

fn copyInto(dst: []u8, src: []const u8) usize {
    const n = @min(dst.len, src.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

fn saveModules() void {
    var file = compat.fs.cwd().createFile("pools.cfg", .{}) catch return;
    defer file.close();
    for (modules[0..module_count]) |m| {
        file.print("{s}\t{s}\t{d}\t{s}\t{s}\t{d}\t{s}\t{s}\n", .{ m.name[0..m.name_len], m.algo[0..m.algo_len], m.port, if (m.on) "1" else "0", m.merge[0..m.merge_len], m.bonus, m.source[0..m.source_len], m.wallet[0..m.wallet_len] }) catch return;
    }
    file.print("#house\t{s}\n#data\t{s}\n", .{ if (house_on) "1" else "0", if (keep_all) "all" else "totals" }) catch return;
    configured = module_count > 0;
}

fn loadModules() void {
    const raw = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, "pools.cfg", 1 << 16) catch return;
    var it = std.mem.splitScalar(u8, raw, '\n');
    while (it.next()) |line| {
        if (line.len < 2) continue;
        if (line.len < 2 or line[0] == '#') {
            if (std.mem.indexOf(u8, line, "house") != null) house_on = std.mem.indexOf(u8, line, "1") != null;
            if (std.mem.indexOf(u8, line, "data") != null) keep_all = std.mem.indexOf(u8, line, "totals") == null;
            continue;
        }
        if (std.mem.startsWith(u8, line, "house") or std.mem.startsWith(u8, line, "data")) continue;
        if (module_count >= modules.len) continue;
        var parts = std.mem.splitScalar(u8, line, '\t');
        const name = parts.next() orelse continue;
        const algo = parts.next() orelse continue;
        const port = std.fmt.parseInt(u16, parts.next() orelse "3333", 10) catch 3333;
        const on = std.mem.eql(u8, parts.next() orelse "1", "1");
        const merge = parts.next() orelse "none";
        const bonus = std.fmt.parseInt(u8, parts.next() orelse "0", 10) catch 0;
        var m = &modules[module_count];
        m.name_len = copyInto(&m.name, name);
        m.algo_len = copyInto(&m.algo, algo);
        m.port = port;
        m.on = on;
        m.merge_len = copyInto(&m.merge, merge);
        m.bonus = bonus;
        m.source_len = copyInto(&m.source, parts.next() orelse "");
        m.wallet_len = copyInto(&m.wallet, parts.next() orelse "");
        var twin = false;
        for (modules[0..module_count]) |*old| {
            if (old.port == m.port and std.mem.eql(u8, old.name[0..old.name_len], m.name[0..m.name_len])) {
                if (m.source_len > 0) old.* = m.*;
                twin = true;
                break;
            }
        }
        if (!twin) module_count += 1;
    }
    configured = module_count > 0;
}

fn fillMerge(index: isize) void {
    _ = SendMessageA(merge_box, CB_RESETCONTENT, 0, 0);
    if (index < 0 or index >= coins.len) return;
    for (coins[@intCast(index)].merges) |name| {
        _ = SendMessageA(merge_box, CB_ADDSTRING, 0, @bitCast(@intFromPtr(name.ptr)));
    }
    _ = SendMessageA(merge_box, CB_SETCURSEL, 0, 0);
}

fn paintSettingsList() void {
    _ = SendMessageA(settings_list, LB_RESETCONTENT, 0, 0);
    for (modules[0..module_count]) |m| {
        var line: [96]u8 = undefined;
        const text = std.fmt.bufPrintSentinel(&line, "{s}  {s}:{d}  {s}  {s}", .{ m.name[0..m.name_len], m.algo[0..m.algo_len], m.port, if (m.on) "running" else "stopped", if (m.source_len == 0) "no source" else m.source[0..m.source_len] }, 0) catch continue;
        _ = SendMessageA(settings_list, LB_ADDSTRING, 0, @bitCast(@intFromPtr(text.ptr)));
    }
}

fn paintLines(text: []const u8) void {
    _ = SendMessageA(report_box, LB_RESETCONTENT, 0, 0);
    var held: [72][200]u8 = undefined;
    var nline: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        if (nline + 1 >= held.len) {
            const more = "more lines are at http://127.0.0.1:8080/api/doctor";
            @memcpy(held[nline][0..more.len], more);
            held[nline][more.len] = 0;
            _ = SendMessageA(report_box, LB_ADDSTRING, 0, @bitCast(@intFromPtr(&held[nline])));
            break;
        }
        const n = @min(line.len, held[nline].len - 1);
        @memcpy(held[nline][0..n], line[0..n]);
        held[nline][n] = 0;
        _ = SendMessageA(report_box, LB_ADDSTRING, 0, @bitCast(@intFromPtr(&held[nline])));
        nline += 1;
    }
}

fn showReport() void {
    const text = @import("pool.zig").reportText(std.heap.page_allocator) catch return;
    var head: [240]u8 = undefined;
    const head_s = @import("modules.zig").sentence(&head);
    setText(summary, head_s);
    var stage_buf: [180]u8 = undefined;
    const stage = @import("chain.zig").stageLine(&stage_buf);
    if (settings_hwnd != null and stage.len > 10) setText(action_line, stage);
    if (settings_hwnd != null) {
        const pct = @import("chain.zig").progress();
        _ = SendMessageA(progress_bar, PBM_SETPOS, pct, 0);
    }
    paintLines(text);
}

fn checkWorker() void {
    const report = @import("ops.zig").run(std.heap.page_allocator, .{ .probe = true, .config = true, .live = true, .files = true, .expect_signon = true, .expect_listen = true });
    check_len = @import("ops.zig").format(&check_buf, &report);
    check_ready = true;
    check_busy = false;
}

fn beginCheck() void {
    if (check_busy) return;
    check_busy = true;
    check_hold = true;
    setText(summary, "Checking share math, templates, and ports.");
    const thread = std.Thread.spawn(.{}, checkWorker, .{}) catch {
        check_busy = false;
        check_hold = false;
        setText(summary, "The check could not start.");
        return;
    };
    thread.detach();
}

fn showCheck() void {
    check_ready = false;
    check_hold = true;
    paintLines(check_buf[0..check_len]);
    var line: [220]u8 = undefined;
    const text = std.fmt.bufPrintSentinel(&line, "{s}. Refresh returns to the live report.", .{@import("ops.zig").headline()}, 0) catch return;
    setText(summary, text);
}

fn addModule() void {
    const picked = SendMessageA(coin_box, CB_GETCURSEL, 0, 0);
    if (picked < 0) return;
    const coin = coins[@intCast(picked)];
    var m: *Module = undefined;
    var existing = false;
    for (modules[0..module_count]) |*old| {
        if (old.port == coin.port and std.mem.eql(u8, old.name[0..old.name_len], coin.name)) {
            m = old;
            existing = true;
            break;
        }
    }
    if (!existing) {
        if (module_count >= modules.len) return setText(summary, "Eight modules is the room.");
        m = &modules[module_count];
        module_count += 1;
    }
    m.name_len = copyInto(&m.name, coin.name);
    m.algo_len = copyInto(&m.algo, coin.algo);
    m.port = coin.port;
    m.on = true;
    if (SendMessageA(merge_check, BM_GETCHECK, 0, 0) == 1) {
        var merge: [24]u8 = undefined;
        m.merge_len = copyInto(&m.merge, textOf(merge_box, &merge));
    } else m.merge_len = copyInto(&m.merge, "none");
    m.bonus = switch (SendMessageA(bonus_box, CB_GETCURSEL, 0, 0)) {
        1 => 5,
        2 => 10,
        else => 0,
    };
    house_on = SendMessageA(house_check, BM_GETCHECK, 0, 0) == 1;
    var src: [96]u8 = undefined;
    var wal: [64]u8 = undefined;
    m.source_len = copyInto(&m.source, textOf(source_box, &src));
    if (std.mem.startsWith(u8, m.source[0..m.source_len], "https://")) {
        setText(summary, "That is a codebase. Put it in Codebase, not Jobs from.");
    }
    m.wallet_len = copyInto(&m.wallet, textOf(wallet_box, &wal));
    if (m.source_len > 0 and !std.mem.startsWith(u8, m.source[0..m.source_len], "https://")) {
        const chain = @import("chain.zig");
        chain.setFeed(m.port, coin.algo, m.source[0..m.source_len]);
        chain.setWallet(m.port, m.wallet[0..m.wallet_len]);
        chain.setMerge(m.port, m.merge[0..m.merge_len]);
    }
    saveModules();
    paintSettingsList();
    showReport();
}

fn toggleModule() void {
    const i = SendMessageA(settings_list, LB_GETCURSEL, 0, 0);
    if (i < 0 or i >= module_count) return;
    modules[@intCast(i)].on = !modules[@intCast(i)].on;
    saveModules();
    paintSettingsList();
    showReport();
}

fn which(cmd: []const u8) bool {
    const tries = [_][]const u8{ "where", "which" };
    for (tries) |tool| {
        var proc = compat.Child.init(&.{ tool, cmd }, std.heap.page_allocator);
        proc.stdout_behavior = .Ignore;
        proc.stderr_behavior = .Ignore;
        const term = proc.spawnAndWait() catch continue;
        if (term == .Exited and term.Exited == 0) return true;
    }
    const common = [_][]const u8{
        "C:\\Program Files\\Git\\cmd\\git.exe",
        "C:\\Program Files (x86)\\Git\\cmd\\git.exe",
    };
    for (common) |path| {
        compat.fs.cwd().access(path, .{}) catch continue;
        return true;
    }
    return false;
}

fn gitExe() []const u8 {
    const common = [_][]const u8{
        "C:\\Program Files\\Git\\cmd\\git.exe",
        "C:\\Program Files (x86)\\Git\\cmd\\git.exe",
    };
    for (common) |path| {
        compat.fs.cwd().access(path, .{}) catch continue;
        return path;
    }
    return "git";
}

fn toolAt(path: []const u8) bool {
    compat.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn grab(url: []const u8, zip_rel: []const u8, into: []const u8) bool {
    compat.fs.cwd().makePath("tools") catch return false;
    compat.fs.cwd().makePath(into) catch return false;
    const curls = [_][]const u8{ "curl.exe", "curl" };
    var got = false;
    for (curls) |curl| {
        var proc = compat.Child.init(&.{ curl, "-L", "--fail", "--retry", "2", "-o", zip_rel, url }, std.heap.page_allocator);
        proc.stdout_behavior = .Ignore;
        proc.stderr_behavior = .Ignore;
        const term = proc.spawnAndWait() catch continue;
        if (term == .Exited and term.Exited == 0) {
            got = true;
            break;
        }
    }
    if (!got) return false;
    const tars = [_][]const u8{ "tar.exe", "tar" };
    for (tars) |tar| {
        var unpack = compat.Child.init(&.{ tar, "-xf", zip_rel, "-C", into }, std.heap.page_allocator);
        unpack.stdout_behavior = .Ignore;
        unpack.stderr_behavior = .Ignore;
        const term = unpack.spawnAndWait() catch continue;
        if (term == .Exited and term.Exited == 0) return true;
    }
    return false;
}

fn ensureGit() []const u8 {
    const chain = @import("chain.zig");
    if (toolAt("tools/git/cmd/git.exe")) return "tools/git/cmd/git.exe";
    if (which("git")) return gitExe();
    chain.setStage("fetching", "git is missing. Downloading MinGit, about 38 MB.");
    const ok = grab("https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/MinGit-2.56.0.2-64-bit.zip", "tools/mingit.zip", "tools/git");
    if (ok and toolAt("tools/git/cmd/git.exe")) return "tools/git/cmd/git.exe";
    return "";
}

fn ensureCompiler() bool {
    const chain = @import("chain.zig");
    if (toolAt("tools/mingw64/bin/mingw32-make.exe") or toolAt("tools/mingw64/bin/gcc.exe")) return true;
    if (which("make") or which("cmake") or which("mingw32-make") or which("gcc")) return true;
    chain.setStage("fetching", "compiler is missing. Downloading gcc, make, and cmake, about 260 MB.");
    const ok = grab("https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r2/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r2.zip", "tools/mingw.zip", "tools");
    return ok and (toolAt("tools/mingw64/bin/mingw32-make.exe") or toolAt("tools/mingw64/bin/gcc.exe"));
}

fn canReach(host: []const u8) bool {
    var proc = compat.Child.init(&.{ "ping", "-n", "1", "-w", "3000", host }, std.heap.page_allocator);
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    const term = proc.spawnAndWait() catch return true;
    return term == .Exited and term.Exited == 0;
}

const Official = struct { url: []const u8, zip: []const u8, into: []const u8, bin: []const u8, why: []const u8 };

fn official(name: []const u8) ?Official {
    if (std.mem.eql(u8, name, "Bitcoin")) return .{
        .url = "https://bitcoincore.org/bin/bitcoin-core-31.1/bitcoin-31.1-win64.zip",
        .zip = "tools/bitcoin.zip",
        .into = "coin-bin/Bitcoin",
        .bin = "coin-bin/Bitcoin/bitcoin-31.1/bin/bitcoind.exe",
        .why = "Bitcoin Core is not a bare make. Downloading the official node.",
    };
    if (std.mem.eql(u8, name, "Litecoin")) return .{
        .url = "https://download.litecoin.org/litecoin-0.21.5.8/win/litecoin-0.21.5.8-win64.zip",
        .zip = "tools/litecoin.zip",
        .into = "coin-bin/Litecoin",
        .bin = "coin-bin/Litecoin/litecoin-0.21.5.8/bin/litecoind.exe",
        .why = "Litecoin is autotools. A bare make fails at once. Downloading the official node.",
    };
    if (std.mem.eql(u8, name, "Dogecoin")) return .{
        .url = "https://github.com/dogecoin/dogecoin/releases/download/v1.14.9/dogecoin-1.14.9-win64.zip",
        .zip = "tools/dogecoin.zip",
        .into = "coin-bin/Dogecoin",
        .bin = "coin-bin/Dogecoin/dogecoin-1.14.9/bin/dogecoind.exe",
        .why = "Dogecoin Core is not a bare make. Downloading the official node.",
    };
    return null;
}

fn fetchWorker(repo: [180]u8, len: usize, port: u16, algo: [16]u8, algo_len: usize, name: [32]u8, name_len: usize) void {
    const typed = repo[0..len];
    const chain = @import("chain.zig");
    if (official(name[0..name_len])) |rel| {
        chain.setStage("downloading", rel.why);
        if (!grab(rel.url, rel.zip, rel.into) or !toolAt(rel.bin)) {
            chain.setStage("failed", "could not download the official node. See tools/ and the network.");
            return;
        }
        chain.setStage("connecting", "official node is on disk. starting it");
        chain.launchBinary(port, algo[0..algo_len], name[0..name_len], rel.bin);
        return;
    }
    chain.setStage("checking", "looking for git");
    const git = ensureGit();
    if (git.len == 0) {
        chain.setStage("failed", "could not download git. See tools/ and your network.");
        return;
    }
    chain.setStage("checking", "can this machine reach github.com");
    if (!canReach("github.com")) {
        chain.setStage("failed", "no route to github.com. Check the network.");
        return;
    }
    chain.setStage("downloading", "git clone");
    const coin_name = compat.fs.path.stem(typed);
    compat.fs.cwd().makePath("coin-src") catch {
        chain.setStage("failed", "could not make coin-src");
        return;
    };
    var dest_buf: [200]u8 = undefined;
    const dest = std.fmt.bufPrint(&dest_buf, "coin-src/{s}", .{coin_name}) catch return;
    compat.fs.cwd().deleteTree(dest) catch {};
    var errlog = compat.fs.cwd().createFile("clone.err", .{}) catch return;
    var clone = compat.Child.init(&.{ git, "clone", "--depth", "1", "--progress", typed, dest }, std.heap.page_allocator);
    clone.stderr_behavior = .Pipe;
    clone.spawn() catch {
        errlog.close();
        chain.setStage("failed", "git would not start");
        return;
    };
    var err_buf: [600]u8 = undefined;
    const err_n = if (clone.stderr) |s| s.read(&err_buf) catch 0 else 0;
    errlog.writeAll(err_buf[0..err_n]) catch {};
    errlog.close();
    const term = clone.wait() catch {
        chain.setStage("failed", "git did not finish");
        return;
    };
    if (!(term == .Exited and term.Exited == 0)) {
        var why: [100]u8 = undefined;
        const slice = if (err_n > 0) err_buf[0..@min(err_n, 90)] else "unknown, see clone.err";
        const n = @min(slice.len, why.len);
        @memcpy(why[0..n], slice[0..n]);
        chain.setStage("failed", why[0..n]);
        return;
    }
    chain.setStage("cloned", "codebase is on disk");
    var file = compat.fs.cwd().createFile("coin.cfg", .{}) catch return;
    file.print("name={s}\nrepo={s}\npath={s}\n", .{ coin_name, typed, dest }) catch {};
    file.close();
    if (!ensureCompiler()) {
        chain.setStage("failed", "could not download the compiler. See tools/ and your network.");
        return;
    }
    chain.setStage("compiling", "gcc, make, and cmake are ready. This can take a while.");
    var script = compat.fs.cwd().createFile("tools/build-coin.cmd", .{}) catch return;
    script.print("@echo off\r\nset PATH=%~dp0mingw64\\bin;%PATH%\r\ncd /d \"{s}\"\r\nif exist Makefile (\r\n  mingw32-make -j2\r\n  exit /b %errorlevel%\r\n)\r\nif exist CMakeLists.txt (\r\n  cmake -S . -B build\r\n  if errorlevel 1 exit /b 1\r\n  cmake --build build -j 2\r\n  exit /b %errorlevel%\r\n)\r\necho no Makefile and no CMakeLists.txt. a bare make cannot build this repo.\r\nexit /b 2\r\n", .{dest}) catch {};
    script.close();
    {
        var log = compat.fs.cwd().createFile("build.log", .{}) catch return;
        log.close();
    }
    var build = compat.Child.init(&.{ "cmd.exe", "/c", "tools\\build-coin.cmd > build.log 2>&1" }, std.heap.page_allocator);
    build.stdout_behavior = .Ignore;
    build.stderr_behavior = .Ignore;
    const built = build.spawnAndWait() catch {
        chain.setStage("failed", "the build tool would not start. see build.log");
        return;
    };
    if (built == .Exited and built.Exited == 0) {
        @import("chain.zig").setStage("compiled", "looking for the node");
        connectAfter(port, algo[0..algo_len], name[0..name_len], dest);
        return;
    }
    var why: [140]u8 = undefined;
    const detail = logTail("build.log", &why);
    @import("chain.zig").setStage("failed", if (detail.len > 0) detail else "build failed. see build.log");
}

fn logTail(path: []const u8, out: []u8) []const u8 {
    const raw = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 1 << 16) catch return "";
    defer std.heap.page_allocator.free(raw);
    var end = raw.len;
    while (end > 0 and (raw[end - 1] == '\n' or raw[end - 1] == '\r' or raw[end - 1] == ' ')) end -= 1;
    if (end == 0) return "";
    var start = end;
    while (start > 0 and raw[start - 1] != '\n' and raw[start - 1] != '\r') start -= 1;
    const line = raw[start..end];
    const n = @min(line.len, out.len);
    @memcpy(out[0..n], line[0..n]);
    return out[0..n];
}

fn connectAfter(port: u16, algo: []const u8, name: []const u8, dest: []const u8) void {
    const chain = @import("chain.zig");
    chain.launchBuilt(port, algo, name, dest);
}

fn cloudflaredPath() []const u8 {
    if (toolAt("tools/cloudflared.exe")) return "tools\\cloudflared.exe";
    return "cloudflared";
}

fn ensureCloudflared() bool {
    if (toolAt("tools/cloudflared.exe") or which("cloudflared")) return true;
    setText(tunnel_line, "Downloading cloudflared. About 20 MB, no account.");
    compat.fs.cwd().makePath("tools") catch return false;
    const url = "https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-windows-amd64.exe";
    const curls = [_][]const u8{ "curl.exe", "curl" };
    for (curls) |curl| {
        var proc = compat.Child.init(&.{ curl, "-L", "--fail", "--retry", "2", "-o", "tools/cloudflared.exe", url }, std.heap.page_allocator);
        proc.stdout_behavior = .Ignore;
        proc.stderr_behavior = .Ignore;
        proc.create_no_window = true;
        const term = proc.spawnAndWait() catch continue;
        if (term == .Exited and term.Exited == 0 and toolAt("tools/cloudflared.exe")) return true;
    }
    return false;
}

fn tunnelUrl(text: []const u8, out: []u8) ?usize {
    var i: usize = 0;
    while (i + 8 < text.len) : (i += 1) {
        if (!std.mem.startsWith(u8, text[i..], "https://")) continue;
        var end = i;
        while (end < text.len and text[end] != ' ' and text[end] != '\n' and text[end] != '\r' and text[end] != '|') end += 1;
        const url = text[i..end];
        if (std.mem.indexOf(u8, url, "trycloudflare.com") == null) continue;
        const n = @min(out.len - 1, url.len);
        @memcpy(out[0..n], url[0..n]);
        out[n] = 0;
        return n;
    }
    return null;
}

fn tunnelWorker() void {
    if (tunnel_live) {
        setText(tunnel_line, "A tunnel is already open. Close it first.");
        return;
    }
    compat.fs.cwd().makePath("tools") catch {};
    if (!ensureCloudflared()) {
        setText(tunnel_line, "Could not download cloudflared. Opening the mining port anyway.");
    } else {
        {
            var blank = compat.fs.cwd().createFile("tools/tunnel.log", .{}) catch return;
            blank.close();
        }
        const shell = std.fmt.bufPrint(&tunnel_shell, "{s} tunnel --url http://127.0.0.1:8080 --no-autoupdate --protocol http2 > tools\\tunnel.log 2>&1", .{cloudflaredPath()}) catch return;
        tunnel_cmd[2] = shell;
        setText(tunnel_line, "Opening the sign-on page and the mining port.");
        tunnel_child = compat.Child.init(&tunnel_cmd, std.heap.page_allocator);
        tunnel_child.stdout_behavior = .Ignore;
        tunnel_child.stderr_behavior = .Ignore;
        tunnel_child.create_no_window = true;
        if (tunnel_child.spawn()) |_| {
            tunnel_live = true;
        } else |_| {
            setText(tunnel_line, "cloudflared would not start. Opening the mining port anyway.");
        }
    }
    startMineRelay();
    if (!tunnel_live) return;
    var scratch: [180]u8 = undefined;
    var tick: usize = 0;
    while (tick < 45 and tunnel_live) : (tick += 1) {
        compat.time.sleep(1 * std.time.ns_per_s);
        const log = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, "tools/tunnel.log", 1 << 16) catch continue;
        defer std.heap.page_allocator.free(log);
        if (tunnelUrl(log, &scratch)) |n| {
            _ = SetWindowTextA(tunnel_box, scratch[0..n :0]);
            setText(tunnel_line, "Sign-on is the https address. Miners outside use the mining address.");
            return;
        }
    }
    if (!tunnel_live) return;
    var why: [140]u8 = undefined;
    const detail = logTail("tools/tunnel.log", &why);
    setText(tunnel_line, if (detail.len > 0) detail else "Sign-on tunnel did not print an address. See tools/tunnel.log. The mining address is separate.");
}

fn openTunnel() void {
    const thread = std.Thread.spawn(.{}, tunnelWorker, .{}) catch return;
    thread.detach();
}

fn closeTunnel() void {
    if (!tunnel_live) {
        setText(tunnel_line, "No tunnel is open.");
        return;
    }
    tunnel_live = false;
    tunnel_child.kill();
    var stop_cf = compat.Child.init(&.{ "taskkill", "/F", "/IM", "cloudflared.exe" }, std.heap.page_allocator);
    stop_cf.stdout_behavior = .Ignore;
    stop_cf.stderr_behavior = .Ignore;
    stop_cf.create_no_window = true;
    _ = stop_cf.spawnAndWait() catch {};
    _ = SetWindowTextA(tunnel_box, "");
    setText(tunnel_line, "Tunnel closed. The free address no longer works.");
}

fn miningPort() u16 {
    for (modules[0..module_count]) |m| {
        if (m.on) return m.port;
    }
    return 3333;
}

fn borePath() []const u8 {
    if (toolAt("tools/bore.exe")) return "tools\\bore.exe";
    if (toolAt("tools/bore")) return "tools/bore";
    return "bore";
}

fn ensureBore() bool {
    if (toolAt("tools/bore.exe") or toolAt("tools/bore")) return true;
    var look = compat.Child.init(&.{ "where", "bore" }, std.heap.page_allocator);
    look.stdout_behavior = .Ignore;
    look.stderr_behavior = .Ignore;
    if (look.spawnAndWait()) |term| {
        if (term == .Exited and term.Exited == 0) return true;
    } else |_| {}
    setText(mine_line, "Downloading bore. About 2 MB, no account.");
    return grab("https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-pc-windows-msvc.zip", "tools/bore.zip", "tools") and toolAt("tools/bore.exe");
}

fn mineAddress(text: []const u8, out: []u8) ?usize {
    const at = std.mem.indexOf(u8, text, "bore.pub:") orelse return null;
    var end = at;
    while (end < text.len and text[end] != ' ' and text[end] != '\n' and text[end] != '\r' and text[end] != '"') end += 1;
    const host = text[at..end];
    const wrote = std.fmt.bufPrint(out, "stratum+tcp://{s}", .{host}) catch return null;
    if (wrote.len + 1 > out.len) return null;
    out[wrote.len] = 0;
    return wrote.len;
}

fn startMineRelay() void {
    if (mine_live) return;
    const port = miningPort();
    var local: [96]u8 = undefined;
    const wrote = std.fmt.bufPrint(local[0..95], "stratum+tcp://127.0.0.1:{d}", .{port}) catch return;
    local[wrote.len] = 0;
    _ = SetWindowTextA(mine_box, local[0..wrote.len :0]);
    if (!ensureBore()) {
        setText(mine_line, "The mining relay did not download. Miners on this PC use the address above.");
        return;
    }
    const shell = std.fmt.bufPrint(&mine_shell, "{s} local {d} --to bore.pub > tools\\bore.log 2>&1", .{ borePath(), port }) catch return;
    mine_argv[2] = shell;
    {
        var blank = compat.fs.cwd().createFile("tools/bore.log", .{}) catch return;
        blank.close();
    }
    setText(mine_line, "Publishing the pool port. Miners outside this network use the address it prints.");
    mine_child = compat.Child.init(&mine_argv, std.heap.page_allocator);
    mine_child.stdout_behavior = .Ignore;
    mine_child.stderr_behavior = .Ignore;
    mine_child.create_no_window = true;
    mine_child.spawn() catch {
        setText(mine_line, "bore would not start. Miners on this PC use the address above.");
        return;
    };
    mine_live = true;
    var scratch: [160]u8 = undefined;
    var tick: usize = 0;
    while (tick < 40 and mine_live) : (tick += 1) {
        compat.time.sleep(500 * std.time.ns_per_ms);
        const log = compat.fs.cwd().readFileAlloc(std.heap.page_allocator, "tools/bore.log", 1 << 16) catch continue;
        defer std.heap.page_allocator.free(log);
        if (mineAddress(log, &scratch)) |n| {
            _ = SetWindowTextA(mine_box, scratch[0..n :0]);
            setText(mine_line, "That mining address is outside this network. Point a miner at it.");
            return;
        }
    }
    if (!mine_live) return;
    var why: [140]u8 = undefined;
    const detail = logTail("tools/bore.log", &why);
    setText(mine_line, if (detail.len > 0) detail else "The mining relay did not print an address. See tools/bore.log.");
}

fn mineWorker() void {
    if (mine_live) {
        setText(mine_line, "A mining relay is already open. Close it first.");
        return;
    }
    startMineRelay();
}

fn openMine() void {
    const thread = std.Thread.spawn(.{}, mineWorker, .{}) catch return;
    thread.detach();
}

fn closeMine() void {
    if (!mine_live) {
        setText(mine_line, "No mining relay is open.");
        return;
    }
    mine_live = false;
    mine_child.kill();
    var stop_bore = compat.Child.init(&.{ "taskkill", "/F", "/IM", "bore.exe" }, std.heap.page_allocator);
    stop_bore.stdout_behavior = .Ignore;
    stop_bore.stderr_behavior = .Ignore;
    stop_bore.create_no_window = true;
    _ = stop_bore.spawnAndWait() catch {};
    setText(mine_line, "Mining relay closed. The public port no longer works.");
}

fn fillCoin(index: isize) void {
    if (index < 0) return;
    const coin = coins[@intCast(index)];
    _ = SetWindowTextA(repo_box, coin.repo);
    fillMerge(index);
}

fn startCoin() void {
    const picked = SendMessageA(coin_box, CB_GETCURSEL, 0, 0);
    if (picked < 0) return;
    fillCoin(picked);
    addModule();
    fetchRepo();
}

fn fetchRepo() void {
    var repo: [180]u8 = undefined;
    const typed = textOf(repo_box, &repo);
    if (!std.mem.startsWith(u8, typed, "https://github.com/") and !std.mem.startsWith(u8, typed, "https://gitlab.com/")) {
        return setText(summary, "Codebase must be github.com or gitlab.com.");
    }
    var held: [180]u8 = undefined;
    @memcpy(held[0..typed.len], typed);
    var algo_buf: [16]u8 = undefined;
    var name_buf: [32]u8 = undefined;
    var algo_len: usize = 0;
    var name_len: usize = 0;
    var port: u16 = 3333;
    const picked = SendMessageA(coin_box, CB_GETCURSEL, 0, 0);
    if (picked >= 0) {
        const coin = coins[@intCast(picked)];
        port = coin.port;
        algo_len = @min(algo_buf.len, coin.algo.len);
        @memcpy(algo_buf[0..algo_len], coin.algo);
        name_len = @min(name_buf.len, coin.name.len);
        @memcpy(name_buf[0..name_len], coin.name);
    }
    @import("chain.zig").setStage("downloading", typed);
    setText(summary, "Downloading the codebase.");
    setText(action_line, "Downloading the codebase.");
    const thread = std.Thread.spawn(.{}, fetchWorker, .{ held, typed.len, port, algo_buf, algo_len, name_buf, name_len }) catch return;
    thread.detach();
}

fn settingsProc(window: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        1 => {
            _ = child(window, "STATIC", "COIN", WS_CHILD | WS_VISIBLE, 12, 8, 40, 16, 1);
            coin_box = child(window, "COMBOBOX", "", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 56, 4, 180, 160, 10);
            for (coins) |c| _ = SendMessageA(coin_box, CB_ADDSTRING, 0, @bitCast(@intFromPtr(c.name.ptr)));
            _ = SendMessageA(coin_box, CB_SETCURSEL, 0, 0);
            merge_check = child(window, "BUTTON", "Merge-mine", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 250, 6, 100, 20, 11);
            merge_box = child(window, "COMBOBOX", "", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 354, 4, 120, 120, 12);
            bonus_box = child(window, "COMBOBOX", "", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST, 484, 4, 110, 80, 14);
            inline for ([_][:0]const u8{ "no bonus", "5% house", "10% house" }) |b| _ = SendMessageA(bonus_box, CB_ADDSTRING, 0, @bitCast(@intFromPtr(b.ptr)));
            _ = SendMessageA(bonus_box, CB_SETCURSEL, 0, 0);
            house_check = child(window, "BUTTON", "House mines this one", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 604, 6, 160, 20, 17);
            if (house_on) _ = SendMessageA(house_check, BM_SETCHECK, 1, 0);
            _ = child(window, "STATIC", "CODEBASE", WS_CHILD | WS_VISIBLE, 12, 40, 70, 16, 3);
            _ = child(window, "STATIC", "Known coins fill this. Or paste any github.com link to add your own.", WS_CHILD | WS_VISIBLE, 86, 40, 420, 16, 26);
            repo_box = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 12, 58, 520, 22, 5);
            fillCoin(0);
            _ = child(window, "BUTTON", "Build and open pool", WS_CHILD | WS_VISIBLE, 540, 56, 150, 26, 6);
            _ = child(window, "STATIC", "EXTERNAL POOL", WS_CHILD | WS_VISIBLE, 12, 92, 110, 16, 21);
            _ = child(window, "STATIC", "Optional. A pool or node you already have, for testing or backup.", WS_CHILD | WS_VISIBLE, 126, 92, 400, 16, 27);
            source_box = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 12, 110, 768, 22, 22);
            _ = child(window, "STATIC", "WALLET", WS_CHILD | WS_VISIBLE, 12, 142, 60, 16, 23);
            wallet_box = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 76, 138, 300, 22, 24);
            _ = child(window, "BUTTON", "Save module", WS_CHILD | WS_VISIBLE, 390, 136, 110, 26, 18);
            _ = child(window, "BUTTON", "Start or stop selected", WS_CHILD | WS_VISIBLE, 508, 136, 160, 26, 19);
            action_line = child(window, "STATIC", "Pick a coin, or paste a repo, then Build and open pool.", WS_CHILD | WS_VISIBLE, 12, 172, 500, 16, 28);
            progress_bar = child(window, "msctls_progress32", "", WS_CHILD | WS_VISIBLE, 520, 170, 260, 18, 29);
            _ = SendMessageA(progress_bar, PBM_SETRANGE, 0, 100 << 16);
            _ = SendMessageA(progress_bar, PBM_SETPOS, 0, 0);
            _ = child(window, "STATIC", "MODULES", WS_CHILD | WS_VISIBLE, 12, 192, 80, 16, 4);
            settings_list = child(window, "LISTBOX", "", WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL, 12, 210, 850, 150, 20);
            _ = child(window, "STATIC", "SHOW A FRIEND", WS_CHILD | WS_VISIBLE, 12, 372, 120, 16, 44);
            _ = child(window, "STATIC", "Free tunnel. Sign-on on HTTPS, and the pool port as TCP so miners outside can connect.", WS_CHILD | WS_VISIBLE, 140, 372, 640, 16, 45);
            _ = child(window, "BUTTON", "Open free tunnel", WS_CHILD | WS_VISIBLE, 12, 394, 140, 26, 40);
            _ = child(window, "BUTTON", "Close tunnel", WS_CHILD | WS_VISIBLE, 160, 394, 110, 26, 41);
            tunnel_box = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_READONLY, 280, 396, 580, 22, 42);
            tunnel_line = child(window, "STATIC", "Not open. Friends cannot sign on or mine from outside yet.", WS_CHILD | WS_VISIBLE, 12, 426, 820, 16, 43);
            _ = child(window, "STATIC", "MINING PORT", WS_CHILD | WS_VISIBLE, 12, 452, 110, 16, 48);
            _ = child(window, "STATIC", "The public pool port. Plain stratum, opened with the tunnel.", WS_CHILD | WS_VISIBLE, 130, 452, 520, 16, 49);
            _ = child(window, "BUTTON", "Publish mining port", WS_CHILD | WS_VISIBLE, 12, 474, 160, 26, 46);
            _ = child(window, "BUTTON", "Close mining port", WS_CHILD | WS_VISIBLE, 180, 474, 140, 26, 47);
            mine_box = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_READONLY, 330, 476, 530, 22, 50);
            mine_line = child(window, "STATIC", "Not published. Open the tunnel, or publish this port on its own.", WS_CHILD | WS_VISIBLE, 12, 506, 820, 16, 51);
            paintSettingsList();
            _ = SetFocus(source_box);
            return 0;
        },
        WM_COMMAND => {
            const id = wp & 0xffff;
            if (id == 10 and (wp >> 16) == CBN_SELCHANGE) fillCoin(SendMessageA(coin_box, CB_GETCURSEL, 0, 0));
            if (id == 6) startCoin();
            if (id == 18) addModule();
            if (id == 19) toggleModule();
            if (id == 40) openTunnel();
            if (id == 41) closeTunnel();
            if (id == 46) openMine();
            if (id == 47) closeMine();
            return 0;
        },
        WM_DESTROY => {
            settings_hwnd = null;
            return 0;
        },
        else => {},
    }
    return DefWindowProcA(window, msg, wp, lp);
}

fn openSettings() void {
    if (settings_hwnd) |w| {
        _ = ShowWindow(w, 5);
        return;
    }
    const inst = GetModuleHandleA(null);
    const class = WNDCLASSA{ .lpfnWndProc = settingsProc, .hInstance = inst, .hbrBackground = brush, .lpszClassName = "ThimbleSettings" };
    _ = RegisterClassA(&class);
    settings_hwnd = CreateWindowExA(0, "ThimbleSettings", "Thimble - Settings", WS_OVERLAPPEDWINDOW, 20, 20, 920, 640, main_hwnd, null, inst, null);
    if (settings_hwnd) |w| _ = ShowWindow(w, 5);
}

fn mainProc(window: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        1 => {
            _ = child(window, "STATIC", "POOL", WS_CHILD | WS_VISIBLE, 16, 8, 80, 18, 1);
            summary = child(window, "STATIC", "No modules yet.", WS_CHILD | WS_VISIBLE, 16, 28, 700, 18, 2);
            report_box = child(window, "LISTBOX", "", WS_CHILD | WS_VISIBLE | WS_BORDER | WS_VSCROLL, 16, 52, 760, 400, 22);
            _ = child(window, "BUTTON", "Check this host", WS_CHILD | WS_VISIBLE, 16, 462, 150, 26, ID_CHECK);
            _ = child(window, "STATIC", "Check dials ports and proves the share math. Refresh returns to the live report.", WS_CHILD | WS_VISIBLE, 180, 468, 580, 16, 3);
            _ = SetTimer(window, 1, 1500, null);
            showReport();
            if (!configured) openSettings();
            return 0;
        },
        WM_TIMER => {
            if (check_ready) {
                showCheck();
                return 0;
            }
            if (check_hold or check_busy) return 0;
            showReport();
            return 0;
        },
        WM_COMMAND => {
            switch (wp & 0xffff) {
                ID_SETTINGS => openSettings(),
                ID_REFRESH => {
                    check_hold = false;
                    showReport();
                },
                ID_CHECK => beginCheck(),
                ID_EXIT => PostQuitMessage(0),
                else => {},
            }
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return DefWindowProcA(window, msg, wp, lp);
}

var setup_admin: HWND = undefined;
var setup_pay: HWND = undefined;
var setup_error: HWND = undefined;
var setup_alive = false;

fn setupProc(window: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        1 => {
            _ = child(window, "STATIC", "THIMBLE", WS_CHILD | WS_VISIBLE, 16, 12, 200, 18, 1);
            _ = child(window, "STATIC", "First start writes host.cfg beside this program. The environment overrides it.", WS_CHILD | WS_VISIBLE, 16, 34, 560, 16, 2);
            _ = child(window, "STATIC", "ADMIN TOKEN", WS_CHILD | WS_VISIBLE, 16, 64, 120, 16, 3);
            setup_admin = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 140, 60, 420, 22, 4);
            setText(setup_admin, compat.adminText());
            _ = child(window, "STATIC", "PAY AT SATS", WS_CHILD | WS_VISIBLE, 16, 96, 120, 16, 5);
            setup_pay = child(window, "EDIT", "", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 140, 92, 160, 22, 6);
            setText(setup_pay, if (compat.payText().len > 0) compat.payText() else "100000");
            _ = child(window, "STATIC", "Pool ports stay closed until Settings has a module with a chain source.", WS_CHILD | WS_VISIBLE, 16, 128, 540, 16, 7);
            setup_error = child(window, "STATIC", "", WS_CHILD | WS_VISIBLE, 16, 152, 540, 16, 8);
            _ = child(window, "BUTTON", "Save and open host", WS_CHILD | WS_VISIBLE, 16, 180, 160, 28, 9);
            return 0;
        },
        WM_COMMAND => {
            if ((wp & 0xffff) != 9) return 0;
            var admin_buf: [80]u8 = undefined;
            var pay_buf: [32]u8 = undefined;
            const admin = textOf(setup_admin, &admin_buf);
            const pay = textOf(setup_pay, &pay_buf);
            if (admin.len < 8) {
                setText(setup_error, "Admin token needs 8 or more characters.");
                return 0;
            }
            if ((std.fmt.parseInt(u64, pay, 10) catch 0) == 0) {
                setText(setup_error, "Pay at needs a positive number of satoshis.");
                return 0;
            }
            var admin_keep: [64]u8 = undefined;
            var pay_keep: [24]u8 = undefined;
            const an = @min(admin.len, admin_keep.len);
            const pn = @min(pay.len, pay_keep.len);
            @memcpy(admin_keep[0..an], admin[0..an]);
            @memcpy(pay_keep[0..pn], pay[0..pn]);
            compat.writeHost(admin_keep[0..an], pay_keep[0..pn], compat.rpcText(), compat.upstreamText(), compat.walletText());
            setup_alive = false;
            _ = DestroyWindow(window);
            return 0;
        },
        WM_DESTROY => {
            setup_alive = false;
            return 0;
        },
        else => {},
    }
    return DefWindowProcA(window, msg, wp, lp);
}

fn runSetup() void {
    const inst = GetModuleHandleA(null);
    const class = WNDCLASSA{ .lpfnWndProc = setupProc, .hInstance = inst, .hbrBackground = brush, .lpszClassName = "ThimbleSetup" };
    _ = RegisterClassA(&class);
    const window = CreateWindowExA(0, "ThimbleSetup", "Thimble - Setup", WS_OVERLAPPEDWINDOW, 80, 80, 620, 280, null, null, inst, null) orelse return;
    _ = ShowWindow(window, 5);
    setup_alive = true;
    var message: MSG = undefined;
    while (setup_alive and GetMessageA(&message, null, 0, 0) != 0) {
        _ = TranslateMessage(&message);
        _ = DispatchMessageA(&message);
    }
}

pub fn open() void {
    InitCommonControls();
    loadModules();
    brush = CreateSolidBrush(0x00181012);
    if (compat.host_fresh or compat.force_setup) runSetup();
    const inst = GetModuleHandleA(null);
    const main_class = WNDCLASSA{ .lpfnWndProc = mainProc, .hInstance = inst, .hbrBackground = brush, .lpszClassName = "ThimbleHost" };
    _ = RegisterClassA(&main_class);
    main_hwnd = CreateWindowExA(0, "ThimbleHost", "Thimble - Host", WS_OVERLAPPEDWINDOW, 40, 30, 820, 580, null, null, inst, null).?;
    const bar = CreateMenu();
    const pool_menu = CreatePopupMenu();
    _ = AppendMenuA(pool_menu, MF_STRING, ID_SETTINGS, "Settings...");
    _ = AppendMenuA(pool_menu, MF_STRING, ID_CHECK, "Check this host");
    _ = AppendMenuA(pool_menu, MF_STRING, ID_REFRESH, "Refresh report");
    _ = AppendMenuA(pool_menu, MF_STRING, ID_EXIT, "Exit");
    _ = AppendMenuA(bar, MF_POPUP, @intFromPtr(pool_menu), "Pool");
    _ = SetMenu(main_hwnd, bar);
    _ = ShowWindow(main_hwnd, 5);
    var message: MSG = undefined;
    while (GetMessageA(&message, null, 0, 0) != 0) {
        _ = TranslateMessage(&message);
        _ = DispatchMessageA(&message);
    }
}
