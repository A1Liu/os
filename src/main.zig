const std = @import("std");
const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("shared_values.h");
});
pub const arm = @import("./asm.zig");
pub const mmio = @import("./mmio.zig");
pub const memory = @import("./memory.zig");
pub const interrupts = @import("./interrupts.zig");
pub const globals = @import("./globals.zig").globals;

pub const log_level: std.log.Level = .info;
pub const strip_debug_info = true;
pub const have_error_return_tracing = false;

// TODO:
// page mappings
// page allocators
// interrupt-based mini-uart handler
// scheduler
// syscalls - make everything either really fast or async

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
        mmio.uartWrite("Log failed, message too long\n");
        return;
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

export fn main() callconv(.C) noreturn {
    mmio.init();
    memory.initProtections();
    interrupts.init();

    _ = memory;

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
    , .{});

    var timer_value: u32 = @atomicLoad(u32, &globals.time_counter, .SeqCst);
    while (true) {
        asm volatile ("nop");

        const value = @atomicLoad(u32, &globals.time_counter, .SeqCst);
        if (timer_value != value) {
            timer_value = value;
            std.log.info("Timer is now: {}", .{value});
        }
    }
}
