const std = @import("std");
const os = @import("root");

const arm = os.arm;
const mmio = os.mmio;
const scheduler = os.scheduler;

// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/src/lesson03/src/entry.S
//
// Handlers defined:
// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/src/lesson03/src/irq.c

const invalid_handler_names = [_][]const u8{
    "sync_invalid_el1t",
    "irq_invalid_el1t",
    "fiq_invalid_el1t",
    "error_invalid_el1t",
    "sync_invalid_el1h",
    "fiq_invalid_el1h",
    "error_invalid_el1h",
    "sync_invalid_el0_64",
    "irq_invalid_el0_64",
    "fiq_invalid_el0_64",
    "error_invalid_el0_64",
    "sync_invalid_el0_32",
    "irq_invalid_el0_32",
    "fiq_invalid_el0_32",
    "error_invalid_el0_32",
};

comptime {
    asm (
        \\.align 11
        \\.global interrupt_vectors
        \\interrupt_vectors:
        \\  .align 7
        \\  b  sync_invalid_el1t       // Synchronous EL1t
        \\  .align 7
        \\  b  irq_invalid_el1t        // IRQ EL1t
        \\  .align 7
        \\  b  fiq_invalid_el1t        // FIQ EL1t
        \\  .align 7
        \\  b  error_invalid_el1t      // Error EL1t
        \\  .align 7
        \\  b  sync_invalid_el1h       // Synchronous EL1h
        \\  .align 7
        \\  b  el1_irq                 // IRQ EL1h
        \\  .align 7
        \\  b  fiq_invalid_el1h        // FIQ EL1h
        \\  .align 7
        \\  b  error_invalid_el1h      // Error EL1h
        \\  .align 7
        \\  b  sync_invalid_el0_64     // Synchronous 64-bit EL0
        \\  .align 7
        \\  b  irq_invalid_el0_64      // IRQ 64-bit EL0
        \\  .align 7
        \\  b  fiq_invalid_el0_64      // FIQ 64-bit EL0
        \\  .align 7
        \\  b  error_invalid_el0_64    // Error 64-bit EL0
        \\  .align 7
        \\  b  sync_invalid_el0_32     // Synchronous 32-bit EL0
        \\  .align 7
        \\  b  irq_invalid_el0_32      // IRQ 32-bit EL0
        \\  .align 7
        \\  b  fiq_invalid_el0_32      // FIQ 32-bit EL0
        \\  .align 7
        \\  b  error_invalid_el0_32    // Error 32-bit EL0
    );

    asm ("" ++
            \\el1_irq:
            \\
        ++ RegisterState.save ++
            \\mov x0, sp
            \\bl handleIrq
            \\
        ++ RegisterState.pop ++
            \\
    );

    inline for (invalid_handler_names) |name, idx| {
        const index = std.fmt.comptimePrint("{}", .{idx});

        asm (name ++ ":\n" ++ RegisterState.save ++
                "mov x1, " ++ index ++ "\n" ++
                \\mov x0, sp
                \\mrs x2, esr_el1
                \\mrs x3, elr_el1
                \\bl emptyHandler
        );
    }
}

// copy-paste links to the ARM docs in the error message

const Handler = fn (state: *RegisterState) callconv(.C) void;
const HandlerPtr = fn () callconv(.Naked) void;

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

    elr_el1: u64,
    spsr_el1: u64,

    const size_str = std.fmt.comptimePrint("{}", .{@sizeOf(RegisterState)});

    const save =
        "    sub  sp, sp, " ++ size_str ++ "\n" ++
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
        \\
        \\   mrs  x22, elr_el1
        \\   mrs  x23, spsr_el1
        \\
        \\   stp  x30, x22, [sp, #16 * 15]
        \\   str  x23, [sp, #16 * 16]
        \\
    ;

    const pop =
        \\   ldr  x23, [sp, #16 * 16]
        \\   ldp  x30, x22, [sp, #16 * 15]
        \\
        \\   msr  elr_el1, x22
        \\   msr  spsr_el1, x23
        \\
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
        \\
    ++ "     add  sp, sp, " ++ size_str ++ "\n" ++
        \\   eret
        \\
    ;
};

pub fn initVectors() void {
    asm volatile (
        \\adr    x0, interrupt_vectors        // load VBAR_EL1 with virtual
        \\msr    vbar_el1, x0
        ::: "x0");
}

pub fn enableIrqs() void {
    asm volatile ("msr daifclr, #2");
}

pub fn disableIrqs() void {
    asm volatile ("msr daifset, #2");
}

pub export fn emptyHandler(
    state: *RegisterState,
    index: usize,
    esr: u64,
    elr: u64,
) callconv(.C) noreturn {
    unhandledException(state, invalid_handler_names[index], esr, elr);
}

pub fn unhandledException(
    state: *RegisterState,
    name: []const u8,
    esr: u64,
    elr: u64,
) noreturn {
    _ = state;

    const sp = arm.readSp();

    std.log.err(
        \\Unhandled Exception
        \\  name: {s}
        \\    sp: 0x{x:0>16}
        \\   esr: 0x{x:0>16}
        \\   elr: 0x{x:0>16}
    , .{ name, sp, esr, elr });

    while (true) {
        asm volatile ("nop");
    }
}

const interval: u32 = 20000;
pub var time_counter: u32 = 0;
pub fn initTimer() void {
    {
        const counter_value = mmio.get32(.TIMER_CLO);
        @atomicStore(u32, &time_counter, counter_value, .SeqCst);
        mmio.put32(.TIMER_C1, counter_value + interval);
    }

    mmio.put32(.ENABLE_IRQS_1, mmio.constants.SYSTEM_TIMER_IRQ_1);
}

fn handleTimerInterrupt(state: *RegisterState) void {
    _ = state;

    const prev_value = @atomicRmw(u32, &time_counter, .Add, interval, .SeqCst);
    const next_interrupt_at = prev_value + interval + interval;
    mmio.put32(.TIMER_C1, next_interrupt_at);
    mmio.put32(.TIMER_CS, mmio.constants.TIMER_CS_M1);

    scheduler.timerTick();
}

// Page 113 of peripherals manual
const IRQ_FLAGS = struct {
    const SYSTEM_TIMER_IRQ_1: u32 = 1 << 1;
};

export fn handleIrq(state: *RegisterState) void {
    const irq = mmio.get32(.IRQ_PENDING_1);

    switch (irq) {
        mmio.constants.SYSTEM_TIMER_IRQ_1 => handleTimerInterrupt(state),

        else => {
            const esr = arm.mrs("esr_el1");
            const elr = arm.mrs("elr_el1");
            unhandledException(state, "el1_irq", esr, elr);
        },
    }
}
