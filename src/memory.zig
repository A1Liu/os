const std = @import("std");
const os = @import("root");
const c = os.c;
const mmio = os.mmio;

pub const size = 1024 * 1024 * 1024;

// Creates a series of set bits. Useful when defining bit masks to use in
// communication with hardware.
fn ones(comptime count: u16) std.math.IntFittingRange(0, (1 << count) - 1) {
    comptime {
        const value: std.math.IntFittingRange(0, 1 << count) = 1 << count;
        return value - 1;
    }
}

const mmu_bits = struct {
    // See D5-2726
    const block: u64 = 0b1 << 1;
    const valid: u64 = 0b1 << 0;
    const access: u64 = 0x1 << 10;

    // D4-2735
    const rw_el1: u64 = 0b00 << 6;
    const r_el1: u64 = 0b10 << 6;
};

export var kernel_memory_map_pmd: [4096]u8 align(4096) = @bitCast([4096]u8, pmd_initial);
const pmd_initial = map: {
    @setEvalBranchQuota(2000);

    var pmd = [1]u64{0} ** 512;

    const mmio_base = mmio.MMIO_BASE >> 21;
    for (pmd) |*slot, i| {
        var descriptor: u64 = i << 21;

        descriptor |= mmu_bits.valid;

        // This flag is managed by software and from what I understand it
        // handles page faults, similar to the "present" bit in x64
        descriptor |= mmu_bits.access;

        const mair_bits = if (i < mmio_base) c.MT_NORMAL_NC_FLAGS else c.MT_DEVICE_nGnRnE;
        descriptor |= mair_bits << 2;

        slot.* = descriptor;
    }

    break :map pmd;
};

// These will go into bss and get initialized at runtime to all zeros;
// Page D5-2717 in the reference manual says that when bit[0] is set
// to 0, the entire descriptor is invalid, so that means that most of
// the initialization work is done for us when the kernel BSS is initialized
//
// They need to be initialized at runtime because we can't know the final address
// of these objects in the binary until we get to the linker, where it's already
// too late.
export var kernel_memory_map_pgd: [4096]u8 align(4096) = [1]u8{0} ** 4096;
export var kernel_memory_map_pud: [4096]u8 align(4096) = [1]u8{0} ** 4096;
