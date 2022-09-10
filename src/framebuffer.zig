const os = @import("root");
const std = @import("std");

const mmio = os.mmio;
const mem = os.memory;

pub var pitch: u32 = undefined;
pub var width: u32 = undefined;
pub var height: u32 = undefined;
pub var isrgb: bool = undefined;
pub var buffer: []align(4096) u8 = undefined;

var mbox: [36]u32 align(16) = undefined;

const MBOX_REQUEST: u32 = 0;
const MBOX_TAG_LAST: u32 = 0;
const MBOX_RESPONSE: u32 = 0x80000000;
const MBOX_FULL: u32 = 0x80000000;
const MBOX_EMPTY: u32 = 0x40000000;

const MBOX_CH_PROP = 8;

fn mboxCall(call: u4) bool {
    const mask = ~@as(u32, 0xF);
    const r = @intCast(u32, mem.physicalAddress(&mbox) & mask) | call;

    while (mmio.get32(.MBOX_STATUS) & MBOX_FULL != 0) {
        asm volatile ("nop");
    }

    mmio.put32(.MBOX_WRITE, r);

    while (true) {
        while (mmio.get32(.MBOX_STATUS) & MBOX_EMPTY != 0) {
            asm volatile ("nop");
        }

        if (r == mmio.get32(.MBOX_READ))
            return mbox[1] == MBOX_RESPONSE;
    }
}

pub fn init() !void {
    mbox[0] = 35 * 4;
    mbox[1] = MBOX_REQUEST;

    mbox[2] = 0x48003; //set phy wh
    mbox[3] = 8;
    mbox[4] = 8;
    mbox[5] = 1024; //FrameBufferInfo.width
    mbox[6] = 768; //FrameBufferInfo.height

    mbox[7] = 0x48004; //set virt wh
    mbox[8] = 8;
    mbox[9] = 8;
    mbox[10] = 1024; //FrameBufferInfo.virtual_width
    mbox[11] = 768; //FrameBufferInfo.virtual_height

    mbox[12] = 0x48009; //set virt offset
    mbox[13] = 8;
    mbox[14] = 8;
    mbox[15] = 0; //FrameBufferInfo.x_offset
    mbox[16] = 0; //FrameBufferInfo.y.offset

    mbox[17] = 0x48005; //set depth
    mbox[18] = 4;
    mbox[19] = 4;
    mbox[20] = 32; //FrameBufferInfo.depth

    mbox[21] = 0x48006; //set pixel order
    mbox[22] = 4;
    mbox[23] = 4;
    mbox[24] = 1; //RGB, not BGR preferably

    mbox[25] = 0x40001; //get framebuffer, gets alignment on request
    mbox[26] = 8;
    mbox[27] = 8;
    mbox[28] = 4096; //FrameBufferInfo.pointer
    mbox[29] = 0; //FrameBufferInfo.size

    mbox[30] = 0x40008; //get pitch
    mbox[31] = 4;
    mbox[32] = 4;
    mbox[33] = 0; //FrameBufferInfo.pitch

    mbox[34] = MBOX_TAG_LAST;

    //this might not return exactly what we asked for, could be
    //the closest supported resolution instead

    const call = mboxCall(MBOX_CH_PROP);
    const success = call and mbox[20] == 32 and mbox[28] != 0;

    if (!success) return error.FailedFramebufferInit;

    mbox[28] &= 0x3FFFFFFF; //convert GPU address to ARM address
    width = mbox[5]; //get actual physical width
    height = mbox[6]; //get actual physical height
    pitch = mbox[33]; //get number of bytes per line
    isrgb = mbox[24] != 0; //get the actual channel order

    buffer.ptr = mem.kernelPtr([*]align(4096) u8, mbox[28]);
    buffer.len = mbox[29];
}
