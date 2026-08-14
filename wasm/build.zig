const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    const pozeiden = b.dependency("pozeiden", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "pozeiden_shim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shim.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .imports = &.{
                .{ .name = "pozeiden", .module = pozeiden.module("pozeiden") },
            },
        }),
    });

    // The host calls the exported functions directly, so there is no _start, and the exports must survive dead-code stripping.
    exe.entry = .disabled;
    exe.rdynamic = true;

    b.installArtifact(exe);
}
