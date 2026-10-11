const compat = @import("compat.zig");
const std = @import("std");

const coins = [_]struct { name: []const u8, repo: []const u8, run: []const u8 }{
    .{ .name = "orthal", .repo = "https://github.com/5mil/orthal.git", .run = "cargo build -p agave-validator && ./target/debug/agave-validator" },
    .{ .name = "agave-hybrid", .repo = "https://github.com/5mil/agave-hybrid.git", .run = "cargo build -p agave-validator" },
};

fn usage() void {
    std.debug.print("usage: coin fetch <name|url> | coin list\n", .{});
    std.debug.print("known: orthal, agave-hybrid\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var args = std.process.args();
    _ = args.skip();
    const cmd = args.next() orelse {
        usage();
        return;
    };
    if (std.mem.eql(u8, cmd, "list")) {
        for (coins) |c| std.debug.print("{s}\t{s}\n", .{ c.name, c.repo });
        return;
    }
    if (!std.mem.eql(u8, cmd, "fetch")) {
        usage();
        return;
    }
    const which = args.next() orelse {
        usage();
        return;
    };
    var repo: []const u8 = which;
    var name: []const u8 = "coin";
    var run: []const u8 = "see the coin README";
    if (!std.mem.startsWith(u8, which, "http")) {
        var found = false;
        for (coins) |c| if (std.mem.eql(u8, c.name, which)) {
            repo = c.repo;
            name = c.name;
            run = c.run;
            found = true;
        };
        if (!found) return error.UnknownCoin;
    }
    const dest = try std.fmt.allocPrint(alloc, "coin-src/{s}", .{name});
    var child = compat.Child.init(&.{ "git", "clone", "--depth", "1", repo, dest }, alloc);
    _ = try child.spawnAndWait();
    var file = try compat.fs.cwd().createFile("coin.cfg", .{});
    defer file.close();
    try file.print("name={s}\nrepo={s}\npath={s}\nrun={s}\npool=3333\n", .{ name, repo, dest, run });
    std.debug.print("downloaded {s} into {s}\n", .{ repo, dest });
    std.debug.print("next: {s}\n", .{run});
    std.debug.print("the pool reads coin.cfg and advertises this node on /api/pool\n", .{});
}
