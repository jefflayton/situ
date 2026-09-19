const std = @import("std");
const Build = std.Build;
const Step = std.Build.Step;

const Artifact = struct {
    exe: *Step.Compile,
    install: *Step,
};

const Modules = struct {
    core: *Build.Module,
    store: *Build.Module,
    logic: *Build.Module,
    cli: *Build.Module,
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const modules = buildModules(b, target, optimize);

    const cli = buildCli(b, modules);

    _ = buildCheck(b, modules);
    _ = buildTests(b, modules);

    b.getInstallStep().dependOn(cli.install);
}

fn buildModules(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Modules {
    const sqlite = b.dependency("sqlite", .{ .target = target, .optimize = optimize });
    const serde = b.dependency("serde", .{ .target = target, .optimize = optimize });

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
    cli.addImport("serde", serde.module("serde"));

    return .{ .core = core, .store = store, .logic = logic, .cli = cli };
}

fn buildTests(b: *Build, modules: Modules) *Step {
    const run_step = b.step("test", "Run all tests");

    for ([_]*Build.Module{ modules.core, modules.store, modules.logic, modules.cli }) |m| {
        const t = b.addTest(.{ .root_module = m });
        run_step.dependOn(&b.addRunArtifact(t).step);
    }

    return run_step;
}

/// Semantic analysis only: `generated_bin = null` makes `Step.Compile` pass
/// `-fno-emit-bin`, so the compiler stops before codegen and linking.
///
/// Both an object and a test per module, because neither alone covers the
/// module. An object is rooted at the module, so it reaches `main` and other
/// code no test references; a test binary is rooted at the test runner, so it
/// reaches `test` blocks but never unreferenced normal code.
fn buildCheck(b: *Build, modules: Modules) *Step {
    const step = b.step("check", "Compilation check");

    for ([_]struct { []const u8, *Build.Module }{
        .{ "core", modules.core },
        .{ "logic", modules.logic },
        .{ "store", modules.store },
        .{ "cli", modules.cli },
    }) |entry| {
        const name, const mod = entry;

        const obj = b.addObject(.{ .name = name, .root_module = mod });
        obj.generated_bin = null;
        step.dependOn(&obj.step);

        const t = b.addTest(.{ .name = name, .root_module = mod });
        t.generated_bin = null;
        step.dependOn(&t.step);
    }

    return step;
}

fn buildCli(b: *Build, modules: Modules) Artifact {
    const step = b.step("cli", "Build the cli");

    const mod = modules.cli;

    const exe_opts: Build.ExecutableOptions = .{
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
