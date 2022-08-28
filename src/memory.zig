const std = @import("std");
const os = @import("root");
const c = os.c;
const mmio = os.mmio;

const assert = std.debug.assert;
const BitSet = os.datastruct.BitSet;

extern var _start: u8;
extern var __rodata_start: u8;
extern var __data_start: u8;
extern var __bss_end: u8;

const virtual_base: u64 = 0xffff000000000000;
inline fn physicalAddress(ptr: anytype) u64 {
    const a = @ptrToInt(ptr);
    return a - virtual_base;
}

inline fn kernelPtr(comptime T: type, address: u64) T {
    return @intToPtr(T, address - virtual_base);
}

// Creates a series of set bits. Useful when defining bit masks to use in
// communication with hardware.
fn ones(comptime count: u16) std.math.IntFittingRange(0, (1 << count) - 1) {
    comptime {
        return (1 << count) - 1;
    }
}

const mmu_bits = struct {
    // See D5-2726
    const block: u64 = 0b1 << 1;
    const pte: u64 = 0b1 << 1;
    const valid: u64 = 0b1 << 0;

    // This flag is managed by software and from what I understand it
    // handles page faults, similar to the "present" bit in x64
    const access: u64 = 0x1 << 10;

    // Executable permission bits
    const nx: u64 = 0x1 << 54; // disable execution for non-priveleged
    const px: u64 = 0x1 << 53; // disable execution for priveleged

    // D4-2735
    const rw_el1: u64 = 0b00 << 6;
    const r_el1: u64 = 0b10 << 6;
};

export var kernel_memory_map_pmd: [4096]u8 align(4096) = @bitCast([4096]u8, pmd_initial);
const pmd_initial = map: {
    @setEvalBranchQuota(2000);

    var pmd = [1]u64{0} ** 512;

    const mmio_base = mmio.MMIO_BASE >> 21;

    // Entry 0 of this map gets overwritten at boot-time, but that is
    // not important to the logic here.
    for (pmd) |*slot, i| {
        var descriptor: u64 = i << 21;

        descriptor |= mmu_bits.valid;
        descriptor |= mmu_bits.access;
        descriptor |= mmu_bits.nx;
        descriptor |= mmu_bits.px;

        const mair_bits = if (i < mmio_base) c.MT_NORMAL_NC_FLAGS else c.MT_DEVICE_nGnRnE;
        descriptor |= mair_bits << 2;

        slot.* = descriptor;
    }

    break :map pmd;
};

export var kernel_memory_map_pte: [4096]u8 align(4096) = map: {
    @setEvalBranchQuota(2000);

    var pte = [1]u64{0} ** 512;

    const mair_bits = c.MT_NORMAL_NC_FLAGS << 2;

    for (pte) |*slot, i| {
        var descriptor: u64 = i << 12;

        descriptor |= mmu_bits.valid;
        descriptor |= mmu_bits.pte;
        descriptor |= mmu_bits.access;
        descriptor |= mair_bits;
        descriptor |= mmu_bits.nx;

        // The stack starts at 0x80000 and should not be executable
        if (i < 128) {
            descriptor |= mmu_bits.px;
        }

        slot.* = descriptor;
    }

    break :map @bitCast([4096]u8, pte);
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

fn addressPteBits(ptr: anytype) usize {
    return (@ptrToInt(ptr) >> 12) & 511;
}

pub fn initProtections() void {
    const exe_begin = addressPteBits(&_start);
    const exe_end = addressPteBits(&__rodata_start);
    const ro_end = addressPteBits(&__data_start);

    const pte = @ptrCast(*volatile [512]u64, &kernel_memory_map_pte);

    for (pte[exe_begin..exe_end]) |*slot| {
        slot.* |= mmu_bits.r_el1;
    }

    for (pte[exe_end..ro_end]) |*slot| {
        slot.* |= mmu_bits.r_el1 | mmu_bits.px;
    }

    for (pte[ro_end..]) |*slot| {
        slot.* |= mmu_bits.px;
    }

    asm volatile (
        \\tlbi vmalle1is
        \\DSB ISH
        \\isb
    );
}

const class_count = 12;
const FreeBlock = extern struct {
    class: i64 align(4096),
    next: ?*@This(),
    prev: ?*@This(),
};

const ClassInfo = struct {
    freelist: ?*align(4096) FreeBlock,
    buddes: BitSet,
};

var free_memory: u64 = undefined;

// Note: these are only ever used for safety
var usable_pages: BitSet = undefined;
var free_pages: BitSet = undefined;

// NOTE: The smallest size class is 4kb.
var classes: [class_count]ClassInfo = undefined;

pub fn allocPages(requested_count: u64, best_effort: bool) error{OutOfMemory}![]align(4096) u8 {
    if (requested_count == 0) return &[0]u8{};

    const result = found_class: {
        const Result = struct { class: usize, freelist: *FreeBlock, count: u64 };

        const min_class = std.math.log2_int_ceil(u64, requested_count);
        for (classes[min_class..]) |class, i| {
            const free = class.freelist orelse continue;

            break :found_class Result{
                .count = requested_count,
                .freelist = free,
                .class = i,
            };
        }

        if (!best_effort) return error.OutOfMemory;

        var i = min_class;
        while (i > 0) {
            i -= 1;

            const free = classes[i].freelist orelse continue;

            break :found_class Result{
                .count = @as(u64, 1) << @truncate(u6, i),
                .freelist = free,
                .class = i,
            };
        }

        return error.OutOfMemory;
    };

    const count: u64 = result.count;
    const class: u64 = result.class;
    const freelist: *FreeBlock = result.freelist;

    assert(freelist.class == class);
    classes[class].freelist = freelist.next;
    if (classes[class].freelist) |head| {
        head.prev = null;
    }

    const buf = @ptrCast([*]align(4096) u8, freelist)[0..(count * 4096)];

    const addr = physicalAddress(buf.ptr);
    const begin = addr / 4096;
    const end = begin + count;

    _ = end;
    _ = class;

    return buf;
}
