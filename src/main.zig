comptime {
    const asmStr = std.fmt.comptimePrint;

    asm ("" ++
            \\.global _start  // Execution starts here
            \\_start:
            \\  mrs     x1, mpidr_el1
            \\  and     x1, x1, 3
            \\
            \\  // Check processor ID is main core, else hang
            \\  cbz     x1, main_core
            \\
            \\// We're not on the main core, so infinite loop
            \\proc_hang:
            \\  wfe
            \\  b       proc_hang
            \\
            \\// Reduce privelege of the Kernel down to EL1. Since
            \\// QEMU starts at EL2, but the Raspberry Pi 3b starts
            \\// at EL3, we need to do some silly shit here.
            \\main_core:
        ++ asmStr("ldr   x0, ={}\n", .{SCTLR_VALUE_MMU_DISABLED}) ++
            \\  msr   sctlr_el1, x0
            \\
            \\  mrs x0, CurrentEL
            \\  lsr x0, x0, 2
            \\  cmp x0, 3
            \\  bne check_drop_from_2
            \\
        ++ asmStr("ldr   x0, ={}\n", .{SCR_VALUE}) ++
            \\  msr   scr_el3, x0
            \\
        ++ asmStr("ldr   x0, ={}\n", .{SPSR_VALUE}) ++
            \\  msr   spsr_el3, x0
            \\
            \\  adr   x0, main_core_el1
            \\  msr   elr_el3, x0
            \\  b drop_from_2
            \\
            \\check_drop_from_2:
            \\  cmp x0, 2
            \\  bne proc_hang
            \\
        ++ asmStr("ldr   x0, ={}\n", .{SPSR_VALUE}) ++
            \\  msr   spsr_el2, x0
            \\
            \\  adr   x0, main_core_el1
            \\  msr   elr_el2, x0
            \\
            \\drop_from_2:
        ++ asmStr("ldr   x0, ={}\n", .{HCR_VALUE}) ++
            \\  msr   hcr_el2, x0
            \\
            \\  eret
            \\
            \\main_core_el1:
            \\  // Set stack to start below our code
            \\  ldr     x1, =_start
            \\  mov     sp, x1
            \\
            \\  // Clean the BSS section
            \\  ldr     x1, =__bss_start     // Start address
            \\  ldr     x2, =__bss_end      // Size of the section
            \\
            \\bss_init_loop:
            \\  str     xzr, [x1], 8
            \\  cmp     x1, x2
            \\  blt     bss_init_loop    // Loop if non-zero
            \\
            \\start_kernel:
            \\  // Jump to our kernel main, should be noreturn
            \\  bl      main
            \\  // Just in case, halt the main core too
            \\  b       proc_hang
    );
}

// SCTLR_EL1, System Control Register (EL1), Page 2654 of AArch64-Reference-Manual.
const SCTLR_VALUE_MMU_DISABLED: u32 = value: {
    const SCTLR_RESERVED = (3 << 28) | (3 << 22) | (1 << 20) | (1 << 11);
    const SCTLR_EE_LITTLE_ENDIAN = 0 << 25;
    const SCTLR_I_CACHE_DISABLED = 0 << 12;
    const SCTLR_D_CACHE_DISABLED = 0 << 2;
    const SCTLR_MMU_DISABLED = 0 << 0;

    break :value SCTLR_RESERVED | SCTLR_EE_LITTLE_ENDIAN |
        SCTLR_I_CACHE_DISABLED | SCTLR_D_CACHE_DISABLED | SCTLR_MMU_DISABLED;
};

// HCR_EL2, Hypervisor Configuration Register (EL2), Page 2487 of AArch64-Reference-Manual.
const HCR_VALUE: u32 = 1 << 31;

// SCR_EL3, Secure Configuration Register (EL3), Page 2648 of AArch64-Reference-Manual.
const SCR_VALUE: u32 = value: {
    const SCR_RESERVED = 3 << 4;
    const SCR_RW = 1 << 10;
    const SCR_NS = 1 << 0;
    break :value SCR_RESERVED | SCR_RW | SCR_NS;
};

// SPSR_EL3, Saved Program Status Register (EL3) Page 389 of AArch64-Reference-Manual.
const SPSR_VALUE: u32 = value: {
    const SPSR_MASK_ALL = 7 << 6;
    const SPSR_EL1h = 5 << 0;
    break :value SPSR_MASK_ALL | SPSR_EL1h;
};

const std = @import("std");
const builtin = @import("builtin");

pub const arm = @import("./asm.zig");
pub const mmio = @import("./mmio.zig");
pub const memory = @import("./memory.zig");
pub const interrupts = @import("./interrupts.zig");
pub const globals = @import("./globals.zig").globals;

pub const strip_debug_info = true;
pub const have_error_return_tracing = false;

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

    var buf: [200]u8 = undefined;

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

    // _ = interrupts;

    std.log.info("Kernel Main Begin. Hello, World!", .{});
    std.log.info("{s}", .{"asdf"});

    const el = asm volatile ("mrs %[val], CurrentEL"
        : [val] "=r" (-> u32),
    );

    switch (el >> 2) {
        0 => mmio.uartWrite("Hello, 0!\n"),
        1 => mmio.uartWrite("Hello, 1!\n"),
        2 => mmio.uartWrite("Hello, 2!\n"),
        3 => mmio.uartWrite("Hello, 3!\n"),
        else => mmio.uartWrite("Hello, World!\n"),
    }

    while (true) {
        asm volatile ("nop");
    }
}
