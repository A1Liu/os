comptime {
    asm (
        \\.global _start  // Execution starts here
        \\_start:
        \\  mrs     x1, mpidr_el1
        \\  and     x1, x1, 3
        \\
        \\  // Check processor ID is zero (executing on main core), else hang
        \\  cbz     x1, main_core
        \\
        \\// We're not on the main core, so hang in an infinite wait loop
        \\proc_hang:
        \\  wfe
        \\  b       proc_hang
        \\
        \\// Reduce privelege of the Kernel down to EL1. Since QEMU starts at EL2,
        \\// but the Raspberry Pi 3b starts at EL3, we need to do some silly shit here.
        \\main_core:
        // \\ldr   x0, =SCTLR_VALUE_MMU_DISABLED
        // \\msr   sctlr_el1, x0
        // \\
        // \\ldr   x0, =HCR_VALUE
        // \\msr   hcr_el2, x0
        // \\ldr   x0, =SCR_VALUE
        // \\msr   scr_el3, x0
        // \\ldr   x0, =SPSR_VALUE
        // \\msr   spsr_el3, x0
        // \\adr   x0, main_core_el1
        // \\msr   elr_el3, x0
        // \\eret
        \\
        \\main_core_el1:
        \\  // We're on the main core!
        \\  // Set stack to start below our code
        \\  ldr     x1, =_start
        \\  mov     sp, x1
        \\
        \\  // Clean the BSS section
        \\  ldr     x1, =__bss_start     // Start address
        \\  ldr     w2, =__bss_size      // Size of the section
        \\bss_init_loop:
        \\  cbz     w2, start_kernel     // Quit loop if zero
        \\  str     xzr, [x1], 8
        \\  sub     w2, w2, 1
        \\  cbnz    w2, bss_init_loop    // Loop if non-zero
        \\
        \\start_kernel:
        \\  // Jump to our main() routine in C (make sure it doesn't return)
        \\  bl      main
        \\  b       proc_hang // In case it does return, halt the master core too
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

pub const arm = @import("./asm.zig");
pub const mmio = @import("./mmio.zig");
pub const memory = @import("./memory.zig");

export fn main() callconv(.Naked) noreturn {
    mmio.init();

    mmio.uartWrite("Hello, World!\r\n");

    const el = asm volatile ("mrs %[val], CurrentEL"
        : [val] "=r" (-> u32),
    );

    switch (el >> 2) {
        0 => mmio.uartWrite("Hello, 0!\r\n"),
        1 => mmio.uartWrite("Hello, 1!\r\n"),
        2 => mmio.uartWrite("Hello, 2!\r\n"),
        3 => mmio.uartWrite("Hello, 3!\r\n"),
        else => mmio.uartWrite("Hello, World!\r\n"),
    }

    while (true) {}
}

fn reduceExceptionLevel() void {
    // M'FER if your syntax is just straight up inline ASM from C with
    // extra steps, fucking say that in your docs instead of that long-winded
    // bullshit.
    //
    // Or just include more than ONE FUCKING EXAMPLE. When I'm trying to figure
    // out your fucking asm syntax, I DON'T GIVE ANY SHITS ABOUT USE CASE. YOU
    // DON'T NEED TO MAKE A REAL EXAMPLE JUST FUCKING INCLUDE MULTIPLE EXAMPLES
    // SO I KNOW WHAT THE FUCK YOU'RE TALKING ABOUT WHEN YOU SAY SOMETHING ISN'T
    // OPTIONAL.
    //                          - Albert Liu, Aug 16, 2022 Tue 01:39 EDT

    asm volatile ("msr sctlr_el1, %[x]"
        :
        : [x] "r" (SCTLR_VALUE_MMU_DISABLED),
    );

    asm volatile ("msr hcr_el2, %[x]"
        :
        : [x] "r" (HCR_VALUE),
    );

    asm volatile ("msr scr_el3, %[x]"
        :
        : [x] "r" (SCR_VALUE),
    );

    asm volatile ("msr spsr_el3, %[x]"
        :
        : [x] "r" (SPSR_VALUE),
    );
}
