const std = @import("std");

const Artifact = struct {
    exe: *std.Build.Step.Compile,
    install: *std.Build.Step,
};

const Modules = struct {
    core: *std.Build.Module,
    store: *std.Build.Module,
    logic: *std.Build.Module,
    cli: *std.Build.Module,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check = b.step("check", "Compile-check all");

    const modules = buildModules(b, target, optimize);

    const cli = buildCli(b, modules);
    check.dependOn(&cli.exe.step);

    const tests = buildTests(b, modules);
    check.dependOn(tests);

    b.getInstallStep().dependOn(cli.install);
}

fn buildModules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Modules {
    const sqlite = b.dependency("sqlite", .{ .target = target, .optimize = optimize });

    const core = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core/root.zig"),
    });

    const store = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/store/root.zig"),
    });
    store.addImport("core", core);
    store.addImport("sqlite", sqlite.module("sqlite"));

    const logic = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/logic/root.zig"),
    });
    logic.addImport("core", core);
    logic.addImport("store", store);

    const cli = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/cli/main.zig"),
    });
    cli.addImport("core", core);
    cli.addImport("logic", logic);
    cli.addImport("store", store);

    return .{ .core = core, .store = store, .logic = logic, .cli = cli };
}

fn buildTests(b: *std.Build, modules: Modules) *std.Build.Step {
    const step = b.step("test", "Run all tests");

    for ([_]*std.Build.Module{ modules.core, modules.store, modules.logic, modules.cli }) |m| {
        const t = b.addTest(.{ .root_module = m });
        step.dependOn(&b.addRunArtifact(t).step);
    }

    return step;
}

fn buildCli(b: *std.Build, modules: Modules) Artifact {
    const step = b.step("cli", "Build the cli");

    const mod = modules.cli;

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
