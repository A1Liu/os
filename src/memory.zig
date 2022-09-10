const std = @import("std");
const os = @import("root");

const c = os.c;
const mmio = os.mmio;
const scheduler = os.scheduler;
const framebuffer = os.framebuffer;

const assert = std.debug.assert;
const BitSet = os.datastruct.BitSet;

extern var _start: u8;
extern var __rodata_start: u8;
extern var __data_start: u8;
extern var __bss_end: u8;

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

// ----------------------------------------------------------------------------
//
//                          Global Memory Allocator
//
// ----------------------------------------------------------------------------
//
// This section implements a global memory allocator using the Buddy Allocator
// algorithm.

const virtual_base: u64 = 0xffff000000000000;
pub inline fn physicalAddress(ptr: anytype) u64 {
    const a = @ptrToInt(ptr);
    return a - virtual_base;
}

pub inline fn kernelPtr(comptime T: type, address: u64) T {
    return @intToPtr(T, address + virtual_base);
}

const class_count = 12;
const FreeBlock = extern struct {
    class: u64 align(4096),
    next: ?*@This(),
    prev: ?*@This(),
};

const ClassInfo = struct {
    freelist: ?*align(4096) FreeBlock,
    buddies: BitSet,
};

const BuddyInfo = struct {
    buddy: u64,
    bitset_index: u64,
};

var free_memory: u64 = 0;

// Note: these are only ever used for safety
var usable_pages: BitSet = undefined;
var free_pages: BitSet = undefined;

// NOTE: The smallest size class is 4kb.
//
// Also: right now, the buddy bitset has no meaning for the largest size class,
// since it has no buddy; we may want to change that later
const buddy_max = std.mem.alignForward(os.memory_size, 4096 << class_count);
const buddy_end_page = buddy_max / 4096;

var class0 = [1]u64{0} ** (buddyInfo(buddy_end_page, 0).bitset_index / 64);
var class1 = [1]u64{0} ** (buddyInfo(buddy_end_page, 1).bitset_index / 64);
var class2 = [1]u64{0} ** (buddyInfo(buddy_end_page, 2).bitset_index / 64);
var class3 = [1]u64{0} ** (buddyInfo(buddy_end_page, 3).bitset_index / 64);
var class4 = [1]u64{0} ** (buddyInfo(buddy_end_page, 4).bitset_index / 64);
var class5 = [1]u64{0} ** (buddyInfo(buddy_end_page, 5).bitset_index / 64);
var class6 = [1]u64{0} ** (buddyInfo(buddy_end_page, 6).bitset_index / 64);
var class7 = [1]u64{0} ** (buddyInfo(buddy_end_page, 7).bitset_index / 64);
var class8 = [1]u64{0} ** (buddyInfo(buddy_end_page, 8).bitset_index / 64);
var class9 = [1]u64{0} ** (buddyInfo(buddy_end_page, 9).bitset_index / 64);
var class10 = [1]u64{0} ** (buddyInfo(buddy_end_page, 10).bitset_index / 64);

// This initial value is valid for an initial set-up where all memory is used.
var classes = classes: {
    var classes_value: [class_count]ClassInfo = undefined;

    const class_arrays = [_][]u64{
        &class0, &class1, &class2,  &class3,
        &class4, &class5, &class6,  &class7,
        &class8, &class9, &class10,
    };

    for (class_arrays) |array, i| {
        classes_value[i] = .{
            .buddies = BitSet.initRaw(array, buddyInfo(buddy_end_page, i).bitset_index),
            .freelist = null,
        };
    }

    classes_value[11] = .{
        .buddies = BitSet.initRaw(&.{}, 0),
        .freelist = null,
    };

    break :classes classes_value;
};

// TODO: add a bigger-arena freelist, for allocations that go beyond the max
// class size?

pub fn initAllocator() void {
    // The `classes` object starts in a valid state, whose meaning is "all data
    // is allocated." This means we can safely just release the pages that
    // are usable.
    const begin = @ptrCast([*]align(4096) u8, @alignCast(4096, &__bss_end));
    const end = mmio.MMIO_BASE;

    const page_count = (end - @ptrToInt(begin)) / 4096;
    releasePagesImpl(begin, @intCast(u32, page_count));
}

fn buddyInfo(page: u64, class: u6) BuddyInfo {
    // assert(is_aligned(page, 1 << class));

    return BuddyInfo{
        .buddy = page ^ (@as(u64, 1) << class),
        .bitset_index = page >> (class + 1),
    };
}

fn addToFreelist(page: u64, class: u64) void {
    // assert(is_aligned(page, 1 << class));

    const block = kernelPtr(*FreeBlock, page * 4096);
    const info = &classes[class];

    block.class = class;
    block.prev = null;
    block.next = info.freelist;

    if (info.freelist) |head| {
        head.prev = block;
    }

    info.freelist = block;
}

fn removeFromFreelist(page: u64, class: u64) void {
    // assert(class < CLASS_COUNT);
    // assert(is_aligned(page, 1 << class));

    const block = kernelPtr(*FreeBlock, page * 4096);
    const info = &classes[class];

    if (block.next) |next| next.prev = block.prev;
    if (block.prev) |prev| prev.next = block.next else {
        assert(info.freelist == block);

        info.freelist = block.next;
    }
}

pub fn allocPages(requested_count: u32, best_effort: bool) error{OutOfMemory}![]align(4096) u8 {
    if (requested_count == 0) return &[0]u8{};

    scheduler.preemptDisable();
    defer scheduler.preemptEnable();

    const result = found_class: {
        const Result = struct { class: u6, freelist: *FreeBlock, count: u64 };

        const min_class = std.math.log2_int_ceil(u32, requested_count);
        for (classes[min_class..]) |class, i| {
            const free = class.freelist orelse continue;

            break :found_class Result{
                .count = requested_count,
                .freelist = free,
                .class = @intCast(u6, i + min_class),
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

    const count = result.count;
    const class = result.class;
    const freelist = result.freelist;

    // Pop from the freelist
    assert(freelist.class == class);
    classes[class].freelist = freelist.next;
    if (classes[class].freelist) |head| {
        head.prev = null;
    }

    const size = count * 4096;
    const buf = @ptrCast([*]align(4096) u8, freelist)[0..size];
    free_memory -= size;

    const addr = physicalAddress(buf.ptr);
    const begin = addr / 4096;
    const end = begin + count;
    _ = end;

    // TODO: safety checks
    // assert(all are usable);
    // assert(all are free);
    // set free pages to not free

    if (class != class_count - 1) {
        const index = buddyInfo(begin, class).bitset_index;
        assert(classes[class].buddies.isSet(index));
        classes[class].buddies.unset(index);
    }

    var i = class;
    var page = begin;
    var remaining = count;

    while (remaining > 0 and i > 0) : (i -= 1) {
        const child_class = i - 1;
        const info = &classes[child_class];
        const child_size = @as(u64, 1) << child_class;
        const index = buddyInfo(page, child_class).bitset_index;

        assert(info.buddies.isSet(index) == false);

        if (remaining > child_size) {
            remaining -= child_size;
            page += child_size;
            continue;
        }

        addToFreelist(page + child_size, child_class);
        info.buddies.set(index);

        if (remaining == child_size) break;
    }

    std.log.info("allocated {*}..{*}", .{ buf.ptr, buf.ptr + buf.len });
    return buf;
}

fn releasePagesImpl(data: [*]align(4096) u8, count: u32) void {
    scheduler.preemptDisable();
    defer scheduler.preemptEnable();

    const addr = physicalAddress(data);
    // assert(addr == align_down(addr, _4KB));

    const begin = addr / 4096;
    const end = begin + count;

    // assert(BitSet__get_all(MemGlobals.usable_pages, begin, end));
    // assert(!BitSet__get_any(MemGlobals.free_pages, begin, end));

    var free_page = begin;
    page: while (free_page < end) : (free_page += 1) {
        // TODO should probably do some math here to not have to iterate over every
        // page in data

        var page = free_page;
        for (classes[0..(class_count - 1)]) |*info, class| {
            // assert(is_aligned(page, 1 << class));
            const buds = buddyInfo(page, @truncate(u6, class));

            const buddy_is_free = info.buddies.isSet(buds.bitset_index);
            info.buddies.setValue(buds.bitset_index, !buddy_is_free);

            if (!buddy_is_free) {
                addToFreelist(page, class);
                continue :page;
            }

            removeFromFreelist(buds.buddy, class);
            page = std.math.min(page, buds.buddy);
        }

        // assert(is_aligned(page, 1 << (CLASS_COUNT - 1)));
        addToFreelist(page, class_count - 1);
    }

    free_memory += count * 4096;
    // BitSet__set_range(MemGlobals.free_pages, begin, end, true);
}

pub fn releasePages(data: [*]align(4096) u8, count: u32) void {
    releasePagesImpl(data, count);
    std.log.info("freed {*}..{*}", .{ data, data + count * 4096 });
}
