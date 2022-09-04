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
pub const globals = @import("./globals.zig").globals;
pub const datastruct = @import("./datastruct.zig");

pub const log_level: std.log.Level = .info;
pub const strip_debug_info = true;
pub const have_error_return_tracing = false;

// TODO:
// page mapping utilities
// interrupt-based mini-uart handler
// syscalls - make everything either really fast or async
// frame buffer

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    _ = scope;
    _ = message_level;

    var buf: [256]u8 = undefined;
    const output = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch {
        panic("Log failed, message too long", null);
    };

    mmio.uartWrite(output);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);

    _ = error_return_trace;

    mmio.uartWrite("PANICKED: ");
    mmio.uartWrite(msg);
    mmio.uartWrite("\n");

    while (true) {
        asm volatile ("nop");
    }
}

fn printTask2(interval: u64) callconv(.C) void {
    var timer_value: u32 = @atomicLoad(u32, &globals.time_counter, .SeqCst);
    while (true) {
        asm volatile ("nop");

        const value = @atomicLoad(u32, &globals.time_counter, .SeqCst);
        if (value - timer_value > interval) {
            timer_value = value;
            std.log.info("- Mimer: {}", .{value});
        }

        scheduler.schedule();
    }
}

fn printTask(interval: u64) callconv(.C) void {
    var timer_value: u32 = @atomicLoad(u32, &globals.time_counter, .SeqCst);
    while (true) {
        asm volatile ("nop");

        const value = @atomicLoad(u32, &globals.time_counter, .SeqCst);
        if (value - timer_value > interval) {
            timer_value = value;
            std.log.info("  Timer: {}", .{value});
        }

        scheduler.schedule();
    }
}

export fn main() callconv(.C) noreturn {
    mmio.init();
    memory.initProtections();

    interrupts.initVectors();

    scheduler.init();

    memory.initAllocator();

    // This doesn't work when these two are moved around; something's
    // obviously wrong but I have no idea what.
    interrupts.initTimer();
    interrupts.enableIrqs();

    const page = memory.allocPages(1, false) catch unreachable;
    std.debug.assert(page.len == 4096);
    memory.releasePages(page.ptr, 1);
    const page2 = memory.allocPages(1, false) catch unreachable;
    std.debug.assert(page.ptr == page2.ptr);
    std.debug.assert(page.len == page2.len);

    const page3 = memory.allocPages(20, false) catch unreachable;
    std.debug.assert(page3.ptr != page2.ptr);
    std.debug.assert(page3.len != page2.len);

    const sp = arm.readSp();
    std.log.info("main sp: {x}", .{sp});

    const el = asm volatile ("mrs %[val], CurrentEL"
        : [val] "=r" (-> u32),
    );

    std.log.info("Kernel Main Begin. Hello, World!", .{});
    std.log.info("Exception Level: {}", .{el >> 2});

    std.log.info("bss value: {*}", .{globals});

    std.log.info(
        \\
        \\-----------------------------------------
        \\
        \\          Entering busy loop
        \\
        \\-----------------------------------------
        \\
    , .{});

    scheduler.Task.init(printTask, 200000) catch unreachable;
    scheduler.Task.init(printTask2, 100000) catch unreachable;

    while (true) {
        // std.log.info("hello\n", .{});
        scheduler.schedule();
    }
}
