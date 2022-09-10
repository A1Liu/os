const os = @import("root");
const std = @import("std");

const mmio = os.mmio;
const physicalAddress = os.memory.physicalAddress;

pub var pitch: u64 = undefined;
pub var buffer: []align(4096) u8 = undefined;

var mbox: [36]u8 align(16) = undefined;

const MBOX_RESPONSE: u32 = 0x80000000;
const MBOX_FULL: u32 = 0x80000000;
const MBOX_EMPTY: u32 = 0x40000000;

fn mboxCall(call: u4) bool {
    const r = @intCast(u32, physicalAddress(&mbox) & 0xF) | call;

    while (mmio.get32(.MBOX_STATUS) & MBOX_FULL != 0) {
        asm volatile ("nop");
    }

    mmio.put32(.MBOX_WRITE, r);
}

pub fn init() void {}
