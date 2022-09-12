const std = @import("std");
const builtin = @import("builtin");

// 1GB
pub const memory_size = 1024 * 1024 * 1024;

pub const c = @cImport({
    @cInclude("shared_values.h");
});

pub const arm = @import("./asm.zig");
pub const mmio = @import("./mmio.zig");
pub const memory = @import("./memory.zig");
pub const interrupts = @import("./interrupts.zig");
pub const scheduler = @import("./scheduler.zig");
pub const framebuffer = @import("./framebuffer.zig");

const datastruct = @import("./datastruct.zig");
pub const BitSet = datastruct.BitSet;

pub const log_level: std.log.Level = .info;
pub const strip_debug_info = true;
pub const have_error_return_tracing = false;

pub const log = mmio.log;
pub const panic = mmio.panic;

const Task = scheduler.Task;

fn printTask2(interval: u64) callconv(.C) void {
    var timer_value: u32 = @atomicLoad(u32, &interrupts.time_counter, .SeqCst);
    while (true) {
        asm volatile ("nop");

        const value = @atomicLoad(u32, &interrupts.time_counter, .SeqCst);
        if (value - timer_value <= interval) {
            Task.stopForNow();
            continue;
        }

        timer_value = value;
        std.log.info("- Mimer: {}", .{value});
    }
}

fn printTask(interval: u64) callconv(.C) void {
    var timer_value: u32 = @atomicLoad(u32, &interrupts.time_counter, .SeqCst);

    var up: bool = true;
    var i: u32 = 0;
    while (true) {
        asm volatile ("nop");

        const value = @atomicLoad(u32, &interrupts.time_counter, .SeqCst);
        if (value - timer_value <= interval) {
            Task.stopForNow();
            continue;
        }

        timer_value = value;
        std.log.info("  Timer: {}", .{value});

        defer i += 1;
        if (i >= 48) {
            i = 0;
            up = !up;
        }

        const a = i / 16;

        var rows = framebuffer.Rows{};
        while (rows.next()) |row| {
            for (row) |*pix_data| {
                if (up) {
                    pix_data[a] +|= 16;
                } else {
                    pix_data[a] -|= 16;
                }
            }
        }
    }
}

export fn main() callconv(.C) noreturn {
    memory.initProtections();

    // interrupts.initVectors();

    // scheduler.init();

    // const fb_result = framebuffer.init();

    // memory.initAllocator();

    mmio.init();

    // This doesn't work when these two are moved around; something's
    // obviously wrong but I have no idea what.
    // interrupts.initInterrupts();
    // interrupts.enableIrqs();

    // {
    //     var rows = framebuffer.Rows{};
    //     while (rows.next()) |row| {
    //         for (row) |*pix_data| {
    //             pix_data[0] = 0;
    //             pix_data[1] = 0;
    //             pix_data[2] = 0;
    //             pix_data[3] = 255;
    //         }
    //     }
    // }

    // const page = memory.allocPages(1, false) catch unreachable;
    // std.debug.assert(page.len == 4096);
    // memory.releasePages(page.ptr, 1);
    // const page2 = memory.allocPages(1, false) catch unreachable;
    // std.debug.assert(page.ptr == page2.ptr);
    // std.debug.assert(page.len == page2.len);

    // const page3 = memory.allocPages(20, false) catch unreachable;
    // std.debug.assert(page3.ptr != page2.ptr);
    // std.debug.assert(page3.len != page2.len);

    // const sp = arm.readSp();
    // std.log.info("main sp: {x}", .{sp});

    // Exception level is 1
    const el = arm.mrs("CurrentEL") >> 2;
    _ = el;

    // std.log.info("Kernel Main Begin. Hello, World!", .{});
    // std.log.info("Exception Level: {}", .{el});

    // fb_result catch {
    //     // handle the error after init is done
    //     std.log.info("framebuffer init failed", .{});
    //     unreachable;
    // };

    // std.log.info("\nframebuffer init succeeded: {}x{}", .{ framebuffer.width, framebuffer.height });
    // std.log.info("  ptr={*},len={}", .{ framebuffer.buffer.ptr, framebuffer.buffer.len });
    // std.log.info("  pitch={}\n", .{framebuffer.pitch});

    // std.log.info("bss value: {*}", .{globals});

    // _ = Task.init(printTask, 200000) catch unreachable;
    // _ = Task.init(printTask2, 100000) catch unreachable;

    // clear the screen
    mmio.uartSpinWrite("\x1Bc");

    mmio.uartSpinWrite(
        \\
        \\-----------------------------------------
        \\
        \\    Kernel Main Begin. Hello, World!
        \\
        \\-----------------------------------------
        \\
    );

    asm volatile ("uaddlv h1, v0.8b");
    asm volatile ("ldr q0, [sp]");
    asm volatile ("fmov d0, x8");
    asm volatile ("cnt   v0.8b, v0.8b");
    asm volatile ("ldur x8, [sp, #-64]");
    asm volatile ("cset w8, ne");

    // untested

    mmio.uartSpinWrite("instructions succeeded\n");

    const a = mmio.fmtIntHex(16);
    mmio.uartSpinWrite("0x");
    mmio.uartSpinWrite(&a);
    mmio.uartSpinWrite("\n");

    // std.log.info("Kernel Main Begin. Hello, {}!", .{10});

    mmio.uartSpinWrite("Log succeeded\n");

    mmio.uartSpinWrite("Entering busy loop\n");

    var i: u32 = 0;
    while (true) : (i += 1) {
        asm volatile ("nop");
    }
}
