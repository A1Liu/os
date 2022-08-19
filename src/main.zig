const std = @import("std");
const builtin = @import("builtin");

pub const arm = @import("./asm.zig");
pub const mmio = @import("./mmio.zig");
pub const memory = @import("./memory.zig");
pub const interrupts = @import("./interrupts.zig");
pub const globals = @import("./globals.zig").globals;

pub const log_level = .debug;
pub const strip_debug_info = true;
pub const have_error_return_tracing = false;

var buf: [200]u8 = [1]u8{0} ** 200;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    _ = scope;
    _ = message_level;
    _ = fmt;
    _ = args;

    // if (@enumToInt(message_level) > @enumToInt(std.log.level)) {
    //     return;
    // }

    const output = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch {
        mmio.uartWrite("Log failed, message too long\n");
        return;
    };

    mmio.uartWrite(output);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);

    _ = error_return_trace;

    mmio.uartWrite("PANICKED!\n");
    mmio.uartWrite(msg);

    while (true) {
        asm volatile ("nop");
    }
}

export fn main() callconv(.C) noreturn {
    mmio.init();

    interrupts.init();

    const el = asm volatile ("mrs %[val], CurrentEL"
        : [val] "=r" (-> u32),
    );

    std.log.info("Kernel Main Begin. Hello, World!", .{});
    std.log.info("Exception Level: {}", .{el >> 2});

    while (true) {
        asm volatile ("nop");
    }
}
