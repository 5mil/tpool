const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server = b.addExecutable(.{
        .name = "thimble",
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(server);

    const run_step = b.step("run", "Run the Thimble host");
    const run = b.addRunArtifact(server);
    run_step.dependOn(&run.step);

    const windows = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu });
    const client = b.addExecutable(.{
        .name = "Thimble",
        .root_source_file = b.path("src/client.zig"),
        .target = windows,
        .optimize = optimize,
    });
    client.subsystem = .Windows;
    client.linkSystemLibrary("winhttp");
    b.installArtifact(client);

    const windows_server = b.addExecutable(.{
        .name = "ThimbleServer",
        .root_source_file = b.path("src/server.zig"),
        .target = windows,
        .optimize = optimize,
    });
    windows_server.subsystem = .Windows;
    windows_server.linkSystemLibrary("user32");
    windows_server.linkSystemLibrary("gdi32");
    b.installArtifact(windows_server);

    const miner = b.addExecutable(.{
        .name = "thimble-miner",
        .root_source_file = b.path("src/miner.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(miner);

    const coin = b.addExecutable(.{
        .name = "thimble-coin",
        .root_source_file = b.path("src/coin.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(coin);
}
