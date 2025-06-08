const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const CrossTarget = Target.Query;
const Feature = Target.Cpu.Feature;

pub fn build(b: *Build) void {
    const features = Target.aarch64.Feature;

    var disabled_features = Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(features.ete));
    disabled_features.addFeature(@intFromEnum(features.fuse_aes));
    disabled_features.addFeature(@intFromEnum(features.neon));
    disabled_features.addFeature(@intFromEnum(features.perfmon));
    disabled_features.addFeature(@intFromEnum(features.use_postra_scheduler));
    const cpu_model = cpu_model: {
        const models = Target.Cpu.Arch.allCpuModels(.aarch64);
        for (models) |model| {
            if (std.mem.eql(u8, model.name, "cortex_a53")) {
                break :cpu_model model;
            }
        }

        unreachable;
    };

    const target = b.resolveTargetQuery(Target.Query{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        .cpu_model = .{ .explicit = cpu_model },
    });

    const optimize = b.standardOptimizeOption(.{});

    const kernel_step = kernel_step: {
        const module = b.createModule(.{ // this line was added
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addIncludePath(b.path("src"));

        const kernel = b.addExecutable(.{
            .name = "kernel.elf",
            .root_module = module,
        });

        kernel.addAssemblyFile(b.path("src/boot.S"));

        kernel.setLinkerScript(b.path("src/link.ld"));

        const copy_kern = b.addInstallArtifact(kernel, .{});
        b.default_step.dependOn(&copy_kern.step);

        // const kernel_step = b.step("kernel", "Build the kernel");
        // kernel_step.dependOn(&kernel.install_step.?.step);

        break :kernel_step kernel;
    };

    b.default_step.dependOn(&kernel_step.step);

    const obj_copy = b.addObjCopy(kernel_step.getEmittedBin(), .{
        .format = .bin,
    });
    // Copy the bin out of the elf
    obj_copy.step.dependOn(&kernel_step.step);

    // Copy the bin to the output directory
    const copy_bin = b.addInstallBinFile(obj_copy.getOutput(), "kernel8.img");

    const iso_step = b.step("img", "Build a usable img");
    iso_step.dependOn(&copy_bin.step);

    {
        const run_cmd_str = &[_][]const u8{
            "qemu-system-aarch64",
            "-M",
            "raspi3b",
            "-cpu",
            "cortex-a57",
            "-serial",
            "null",
            "-chardev",
            "stdio,id=uart1",
            "-serial",
            "chardev:uart1",
            "-kernel",
            "./zig-out/bin/kernel8.img",
        };

        const run_cmd = b.addSystemCommand(run_cmd_str);
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the Kernel in QEMU");
        run_step.dependOn(&run_cmd.step);

        const info_cmd_str = &[_][]const u8{
            "echo",

            \\The GDB Server will open on localhost:1234 .
            \\
            \\Open with LLDB:
            \\  lldb zig-out/bin/kernel.elf
            \\
            \\Then, attach to the server:
            \\  gdb-remote localhost:1234
            \\
            \\Or you can open in VS Code (may not actually work):
            \\  vscode://vadimcn.vscode-lldb/launch?name=Remote%20Attach
        };

        const info_cmd = b.addSystemCommand(info_cmd_str);
        info_cmd.step.dependOn(b.getInstallStep());

        const debug_cmd_str = run_cmd_str ++ &[_][]const u8{
            "-S",
            "-s",
            "-no-reboot",
            "-no-shutdown",
        };

        const debug_cmd = b.addSystemCommand(debug_cmd_str);
        debug_cmd.step.dependOn(&info_cmd.step);

        const debug_step = b.step("debug", "Debug the Kernel in QEMU");
        debug_step.dependOn(&debug_cmd.step);
    }

    {
        const dump_cmd_str = &[_][]const u8{
            "/bin/sh",
            "-c",
            "llvm-objdump --arch-name=aarch64 -D ./zig-out/bin/kernel.elf > ./zig-out/bin/dump.txt",
        };

        const dump_cmd = b.addSystemCommand(dump_cmd_str);
        dump_cmd.step.dependOn(&kernel_step.step);

        const dump_step = b.step("dump", "Obj-Dump the Kernel ELF file");
        dump_step.dependOn(&dump_cmd.step);
    }
}
