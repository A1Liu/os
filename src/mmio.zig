const os = @import("root");
const arm = os.arm;

pub const constants = struct {
    pub const SYSTEM_TIMER_IRQ_1: u32 = 1 << 1;

    pub const TIMER_CS_M1: u32 = 1 << 1;
};

pub const MMIO_BASE: u32 = 0x3F000000;
const GPIO_BASE = MMIO_BASE + 0x200000;
const AUX_BASE = (GPIO_BASE + 0x15000);

const MmioRegister = enum(u32) {
    IRQ_BASIC_PENDING = MMIO_BASE + 0x0000B200,
    IRQ_PENDING_1 = MMIO_BASE + 0x0000B204,
    IRQ_PENDING_2 = MMIO_BASE + 0x0000B208,
    FIQ_CONTROL = MMIO_BASE + 0x0000B20C,
    ENABLE_IRQS_1 = MMIO_BASE + 0x0000B210,
    ENABLE_IRQS_2 = MMIO_BASE + 0x0000B214,
    ENABLE_BASIC_IRQS = MMIO_BASE + 0x0000B218,
    DISABLE_IRQS_1 = MMIO_BASE + 0x0000B21C,
    DISABLE_IRQS_2 = MMIO_BASE + 0x0000B220,
    DISABLE_BASIC_IRQS = MMIO_BASE + 0x0000B224,

    GPFSEL1 = GPIO_BASE + 0x4,
    GPSET0 = GPIO_BASE + 0x1C,
    GPCLR0 = GPIO_BASE + 0x28,
    GPPUD = GPIO_BASE + 0x94, // Controls actuation of pull up/down to ALL GPIO pins.
    GPPUDCLK0 = GPIO_BASE + 0x98, // Controls actuation of pull up/down for specific GPIO pin.

    AUX_ENABLES = AUX_BASE + 0x04,
    AUX_MU_IO_REG = AUX_BASE + 0x40,
    AUX_MU_IER_REG = AUX_BASE + 0x44,
    AUX_MU_IIR_REG = AUX_BASE + 0x48,
    AUX_MU_LCR_REG = AUX_BASE + 0x4C,
    AUX_MU_MCR_REG = AUX_BASE + 0x50,
    AUX_MU_LSR_REG = AUX_BASE + 0x54,
    AUX_MU_MSR_REG = AUX_BASE + 0x58,
    AUX_MU_SCRATCH = AUX_BASE + 0x5C,
    AUX_MU_CNTL_REG = AUX_BASE + 0x60,
    AUX_MU_STAT_REG = AUX_BASE + 0x64,
    AUX_MU_BAUD_REG = AUX_BASE + 0x68,

    // Timer
    TIMER_CS = MMIO_BASE + 0x00003000,
    TIMER_CLO = MMIO_BASE + 0x00003004,
    TIMER_CHI = MMIO_BASE + 0x00003008,
    TIMER_C0 = MMIO_BASE + 0x0000300C,
    TIMER_C1 = MMIO_BASE + 0x00003010,
    TIMER_C2 = MMIO_BASE + 0x00003014,
    TIMER_C3 = MMIO_BASE + 0x00003018,
};

pub inline fn get32(comptime reg: MmioRegister) u32 {
    return @intToPtr(*volatile u32, @enumToInt(reg)).*;
}

pub inline fn put32(comptime reg: MmioRegister, data: u32) void {
    @intToPtr(*volatile u32, @enumToInt(reg)).* = data;
}

// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/docs/lesson01/rpi-os.md#mini-uart-initialization
pub fn init() void {
    var selector = get32(.GPFSEL1);
    selector &= ~@as(u32, 0b111 << 12); // clean gpio14
    selector |= 0b010 << 12; // set alt5 for gpio14
    selector &= ~@as(u32, 0b111 << 15); // clean gpio15
    selector |= 0b010 << 15; // set alt5 for gpio 15
    put32(.GPFSEL1, selector);

    put32(.GPPUD, 0);
    arm.delay(150);
    put32(.GPPUDCLK0, 0b11 << 14);
    arm.delay(150);
    put32(.GPPUDCLK0, 0);

    put32(.AUX_ENABLES, 1); //Enable mini uart (this also enables access to its registers)
    put32(.AUX_MU_CNTL_REG, 0); //Disable auto flow control and disable receiver and transmitter (for now)
    put32(.AUX_MU_IER_REG, 0); //Disable receive and transmit interrupts
    put32(.AUX_MU_LCR_REG, 3); //Enable 8 bit mode
    put32(.AUX_MU_MCR_REG, 0); //Set RTS line to be always high
    put32(.AUX_MU_BAUD_REG, 270); //Set baud rate to 115200

    put32(.AUX_MU_CNTL_REG, 3); //Finally, enable transmitter and receiver
}

pub fn uartWrite(str: []const u8) void {
    for (str) |c| {
        // Wait for UART to become ready to transmit.
        while ((get32(.AUX_MU_LSR_REG) & 0x20) == 0) {}

        put32(.AUX_MU_IO_REG, c);
    }
}
