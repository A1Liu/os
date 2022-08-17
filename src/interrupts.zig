const std = @import("std");
const os = @import("root");
const mmio = os.mmio;

comptime {
    asm (
        \\
    );
}

const Handler = fn (state: *RegisterState) callconv(.Naked) void;

pub const RegisterState = extern struct {
    x0: u64,
    x1: u64,
    x2: u64,
    x3: u64,
    x4: u64,
    x5: u64,
    x6: u64,
    x7: u64,
    x8: u64,
    x9: u64,
    x10: u64,

    x11: u64,
    x12: u64,
    x13: u64,
    x14: u64,
    x15: u64,
    x16: u64,
    x17: u64,
    x18: u64,
    x19: u64,
    x20: u64,

    x21: u64,
    x22: u64,
    x23: u64,
    x24: u64,
    x25: u64,
    x26: u64,
    x27: u64,
    x28: u64,
    x29: u64,
    x30: u64,
};

const save_registers =
    std.fmt.comptimePrint("sub  sp, sp, {}", @sizeOf(RegisterState)) ++
    \\   stp  x0, x1, [sp, #16 * 0]
    \\   stp  x2, x3, [sp, #16 * 1]
    \\   stp  x4, x5, [sp, #16 * 2]
    \\   stp  x6, x7, [sp, #16 * 3]
    \\   stp  x8, x9, [sp, #16 * 4]
    \\   stp  x10, x11, [sp, #16 * 5]
    \\   stp  x12, x13, [sp, #16 * 6]
    \\   stp  x14, x15, [sp, #16 * 7]
    \\   stp  x16, x17, [sp, #16 * 8]
    \\   stp  x18, x19, [sp, #16 * 9]
    \\   stp  x20, x21, [sp, #16 * 10]
    \\   stp  x22, x23, [sp, #16 * 11]
    \\   stp  x24, x25, [sp, #16 * 12]
    \\   stp  x26, x27, [sp, #16 * 13]
    \\   stp  x28, x29, [sp, #16 * 14]
    \\   str  x30, [sp, #16 * 15]
;

const pop_registers =
    \\   ldp  x0, x1, [sp, #16 * 0]
    \\   ldp  x2, x3, [sp, #16 * 1]
    \\   ldp  x4, x5, [sp, #16 * 2]
    \\   ldp  x6, x7, [sp, #16 * 3]
    \\   ldp  x8, x9, [sp, #16 * 4]
    \\   ldp  x10, x11, [sp, #16 * 5]
    \\   ldp  x12, x13, [sp, #16 * 6]
    \\   ldp  x14, x15, [sp, #16 * 7]
    \\   ldp  x16, x17, [sp, #16 * 8]
    \\   ldp  x18, x19, [sp, #16 * 9]
    \\   ldp  x20, x21, [sp, #16 * 10]
    \\   ldp  x22, x23, [sp, #16 * 11]
    \\   ldp  x24, x25, [sp, #16 * 12]
    \\   ldp  x26, x27, [sp, #16 * 13]
    \\   ldp  x28, x29, [sp, #16 * 14]
    \\   ldr  x30, [sp, #16 * 15]
++ std.fmt.comptimePrint("add  sp, sp, {}", @sizeOf(RegisterState)) ++
    \\   eret
;

const IRQ_FLAGS = struct {
    const SYSTEM_TIMER_IRQ_1: u32 = 1 << 1;
};

pub fn createInvalidHandler(comptime name: []const u8) Handler {
    comptime {
        return struct {
            fn handler(state: *RegisterState) callconv(.Naked) void {
                _ = state;

                os.mmio.uartWrite("Got invalid exception: " ++ name ++ "\n");
            }
        }.handler;
    }
}

// First parameter is passed in x9
pub fn handleTimerInterrupt(state: *RegisterState) callconv(.C) void {
    _ = state;
}

pub fn enableIrqs() void {
    mmio.put32(.ENABLE_IRQS_1, IRQ_FLAGS.SYSTEM_TIMER_IRQ_1);
}
