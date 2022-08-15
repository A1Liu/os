const std = @import("std");
const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;

pub fn build(b: *Builder) void {
    // const features = Target.x86.Feature;

    // var disabled_features = Feature.Set.empty;
    // var enabled_features = Feature.Set.empty;

    // disabled_features.addFeature(@enumToInt(features.mmx));
    // disabled_features.addFeature(@enumToInt(features.sse));
    // disabled_features.addFeature(@enumToInt(features.sse2));
    // disabled_features.addFeature(@enumToInt(features.avx));
    // disabled_features.addFeature(@enumToInt(features.avx2));
    // enabled_features.addFeature(@enumToInt(features.soft_float));

    const target = CrossTarget{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        //.cpu_features_sub = disabled_features,
        // .cpu_features_add = enabled_features,
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
}
