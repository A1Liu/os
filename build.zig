const std = @import("std");
const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;

pub fn build(b: *Builder) void {
    const target = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
    };

    const mode = b.standardReleaseOptions();

    const kernel_step = kernel_step: {
        const kernel = b.addExecutable("kernel.elf", "src/main.zig");
        kernel.setTarget(target);
        kernel.setBuildMode(mode);
        kernel.setLinkerScriptPath(.{ .path = "src/link.ld" });
        kernel.install();

        const kernel_step = b.step("kernel", "Build the kernel");
        kernel_step.dependOn(&kernel.install_step.?.step);

        break :kernel_step kernel_step;
    };

    // TODO: zig objcopy will eventually be a thing, and when it is, we can
    // remove the dependency on llvm-objcopy
    const iso_step = iso_step: {
        const iso_cmd_str = &[_][]const u8{
            "llvm-objcopy",
            "-Obinary",
            "zig-out/bin/kernel.elf",
            "zig-out/bin/kernel8.img",
        };

        const iso_cmd = b.addSystemCommand(iso_cmd_str);
        iso_cmd.step.dependOn(kernel_step);

        const iso_step = b.step("img", "Build a usable img");
        iso_step.dependOn(&iso_cmd.step);

        break :iso_step iso_step;
    };

    b.default_step.dependOn(iso_step);

    {
        const run_cmd_str = &[_][]const u8{
            "qemu-system-aarch64",
            "-M",
            "raspi3b",
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
    }

    {
        const dump_cmd_str = &[_][]const u8{
            "/bin/sh",
            "-c",
            "llvm-objdump --arch-name=aarch64 -D ./zig-out/bin/kernel.elf > ./zig-out/bin/dump.txt",
        };

        const dump_cmd = b.addSystemCommand(dump_cmd_str);
        dump_cmd.step.dependOn(kernel_step);

        const dump_step = b.step("dump", "Obj-Dump the Kernel ELF file");
        dump_step.dependOn(&dump_cmd.step);
    }
}
