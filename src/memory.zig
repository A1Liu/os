const std = @import("std");
const os = @import("root");
const c = os.c;
const mmio = os.mmio;

pub const size = 1024 * 1024 * 1024;

// PLAN:
//
// 1. Create mapping offline for 1GB, as array, at comptime
// 2. store mapping in data section
// 3. Write asm for setting mapping and then jumping to correct location
// 4. Profit?

// See D5-2726

const upper_attr_mask: u64 = 0b1111111111111111 << 47;
const reserved_mask: u64 = 0b1 << 11;
const lower_attr_mask: u64 = 0b111111111 << 2;
const block_bit: u64 = 0b1 << 1;
const valid_bit: u64 = 0b1 << 0;

const addr_mask: u64 = ~(upper_attr_mask | reserved_mask | lower_attr_mask | block_bit | valid_bit);

const access_bit: u64 = 0x1 << 10;

// D4-2735
// const rw_el1: u64 = 0b00 << 6;
// const r_el1: u64 = 0b10 << 6;

const pmd_initial = map: {
    @setEvalBranchQuota(2000);

    var pmd = [1]u64{0} ** 512;

    const mmio_base = mmio.MMIO_BASE >> 21;
    for (pmd) |*slot, i| {
        var descriptor: u64 = i << 21;

        descriptor |= valid_bit;

        // This flag is managed by software and from what I understand it
        // handles page faults, similar to the "present" bit in x64
        descriptor |= access_bit;

        if (i < mmio_base) {
            descriptor |= c.MT_NORMAL_NC_FLAGS << 2;
        } else {
            descriptor |= c.MT_DEVICE_nGnRnE << 2;
        }

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
export var kernel_memory_map_pmd: [4096]u8 align(4096) = @bitCast([4096]u8, pmd_initial);

// comptime {
//     const skip = 2;
//     for (pmd_initial) |slot, i| {
//         if (i < skip) continue;
//         @compileError(std.fmt.comptimePrint("{}: {x}", .{ i, slot }));
//     }
// }
