const std = @import("std");

pub fn build(b: *std.Build) void {
    const cli_step = buildCli(b);

    const all = b.step("all", "Build all targets");
    all.dependOn(cli_step);

    const check = b.step("check", "Compile-check all");
    check.dependOn(cli_step);
}

fn buildCli(b: *std.Build) *std.Build.Step {
    const step = b.step("cli", "Build the cli");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core/root.zig"),
    });

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/cli/main.zig"),
    });
    mod.addImport("core", core);

    const exe_opts: std.Build.ExecutableOptions = .{
        .name = "situ",
        .root_module = mod,
    };
    const exe = b.addExecutable(exe_opts);
    const install_exe = b.addInstallArtifact(exe, .{});
    step.dependOn(&install_exe.step);

    const run = b.step("run-cli", "Run the cli");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_exe.step);
    if (b.args) |args| run_cmd.addArgs(args);
    run.dependOn(&run_cmd.step);

    return step;
}
