const std = @import("std");

const Artifact = struct {
    exe: *std.Build.Step.Compile,
    install: *std.Build.Step,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check = b.step("check", "Compile-check all");

    const cli = buildCli(b, target, optimize);

    check.dependOn(&cli.exe.step);

    b.getInstallStep().dependOn(cli.install);
}

fn buildCli(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Artifact {
    const step = b.step("cli", "Build the cli");

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

    return .{ .exe = exe, .install = step };
}
