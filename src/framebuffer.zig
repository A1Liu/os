const os = @import("root");
const std = @import("std");

const mmio = os.mmio;
const mem = os.memory;

pub var pitch: u32 = undefined;
pub var width: u32 = undefined;
pub var height: u32 = undefined;
pub var buffer: []align(4096) volatile u8 = undefined;

const mbox = mmio.mbox;
pub fn init() !void {
    mbox[0] = 35 * 4;
    mbox[1] = mmio.MBOX.REQUEST;

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

    mbox[34] = mmio.MBOX.TAG_LAST;

    //this might not return exactly what we asked for, could be
    //the closest supported resolution instead

    const call = mmio.mboxSpinCall(mmio.MBOX.CH_PROP);
    const success = call and mbox[20] == 32 and mbox[28] != 0;

    buffer = &.{};
    if (!success) return error.FailedFramebufferInit;

    // check the actual channel order
    if (mbox[24] == 0) return error.NotRGB;

    // Not quite sure I understand this one...
    //
    // this is the logic mentioned by the RPi forum post:
    //      https://forums.raspberrypi.com/viewtopic.php?t=155825
    // and also equivalent to code found in a Raspberry Pi 3b+ tutorial:
    //      https://github.com/bztsrc/raspi3-tutorial/blob/master/09_framebuffer/lfb.c
    //
    //                                      - Albert Liu, Sep 10, 2022 Sat 00:14 EDT
    const bus_address_mask: u32 = 0xC0000000;
    mbox[28] &= ~bus_address_mask; //convert GPU address to ARM address

    width = mbox[5]; //get actual physical width
    height = mbox[6]; //get actual physical height
    pitch = mbox[33]; //get number of bytes per line

    buffer.ptr = mem.kernelPtr([*]align(4096) u8, mbox[28]);
    buffer.len = mbox[29];
}
