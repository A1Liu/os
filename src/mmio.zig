const os = @import("root");
const std = @import("std");

const arm = os.arm;
const interrupts = os.interrupts;
const scheduler = os.scheduler;
const mem = os.memory;

const Task = scheduler.Task;

pub const constants = struct {
    pub const SYSTEM_TIMER_IRQ_1: u32 = 1 << 1;

    pub const TIMER_CS_M1: u32 = 1 << 1;
};

// pub const MMIO_BASE: u64 = 0xFFFF00003F000000;
pub const MMIO_BASE: u64 = 0x000000003F000000;
const MBOX_BASE = MMIO_BASE + 0x0000B880;
const GPIO_BASE = MMIO_BASE + 0x200000;
const AUX_BASE = (GPIO_BASE + 0x15000);

const MmioRegister = enum(u64) {
    // Page 112 of peripherals manual
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

    MBOX_READ = MBOX_BASE + 0x00,
    MBOX_POLL = MBOX_BASE + 0x10,
    MBOX_SENDER = MBOX_BASE + 0x14,
    MBOX_STATUS = MBOX_BASE + 0x18,
    MBOX_CONFIG = MBOX_BASE + 0x1C,
    MBOX_WRITE = MBOX_BASE + 0x20,

    GPFSEL1 = GPIO_BASE + 0x4,
    GPSET0 = GPIO_BASE + 0x1C,
    GPCLR0 = GPIO_BASE + 0x28,
    // Controls actuation of pull up/down to ALL GPIO pins.
    GPPUD = GPIO_BASE + 0x94,
    // Controls actuation of pull up/down for specific GPIO pin.
    GPPUDCLK0 = GPIO_BASE + 0x98,

    AUX_IRQ = AUX_BASE + 0x00,
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
    // uart_task = Task.init(uartTask, 0) catch unreachable;
    // queue_head.str = "";
    // queue_head.task = uart_task;
    // queue_tail = &queue_head;

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

    //p 13, Peripherals Manual:
    // - bits 3:2 must be 1 for interrupts to be enabled
    // - bit 1 must be set for transmit interrupts
    // const a: u32 = (1 << 1) | (0x11 << 2);
    // put32(.AUX_MU_IER_REG, a);
    put32(.AUX_MU_IER_REG, 0);

    put32(.AUX_MU_LCR_REG, 3); //Enable 8 bit mode
    put32(.AUX_MU_MCR_REG, 0); //Set RTS line to be always high
    put32(.AUX_MU_BAUD_REG, 270); //Set baud rate to 115200

    put32(.AUX_MU_CNTL_REG, 3); //Finally, enable transmitter and receiver

}

const Node = struct {
    next: ?*@This() = null,
    str: []const u8,
    task: scheduler.Task,
};

var uart_task: Task = undefined;
var queue_head: Node = .{ .str = undefined, .task = undefined };
var queue_tail: *Node = undefined;

pub fn uartTask(_: u64) callconv(.C) void {
    const q_head = &queue_head;
    const q_tail = &queue_tail;

    outer: while (true) {
        for (q_head.str) |c, i| {
            if ((get32(.AUX_MU_LSR_REG) & 0x20) == 0) {
                q_head.str = q_head.str[i..];

                const config = get32(.AUX_MU_IER_REG);
                put32(.AUX_MU_IER_REG, config | (1 << 1));

                Task.sleep();

                continue :outer;
            }

            put32(.AUX_MU_IO_REG, c);
        }

        q_head.task.wake();

        q_head.str = "";
        q_head.task = uart_task;

        const next = next: {
            while (true) {
                if (@atomicLoad(?*Node, &q_head.next, .SeqCst)) |n| break :next n;

                // This is technically not required
                var tail = @atomicLoad(*Node, q_tail, .SeqCst);
                std.debug.assert(tail == q_head);

                Task.sleep();
            }

            unreachable;
        };

        q_head.str = next.str;
        q_head.task = next.task;

        // Publish an initial null value for `next`, because after the next
        // statement, the head might be published to everyone, and setting the
        // `next` field then could cause a race condition.
        q_head.next = null;

        // We try to re-set the tail, expecting that the `next` is the last
        // element.
        //
        // If it fails due to the expected value being incorrect,
        // we can just move on.
        const res = @cmpxchgStrong(*Node, q_tail, next, q_head, .SeqCst, .SeqCst);

        // Try to read atomically from the `next.next` value to get the
        // actual next we should be using. It might not be populated yet,
        // so we need to busy-loop here.
        while (res != null) {
            if (@atomicLoad(?*Node, &next.next, .SeqCst)) |n| {
                q_head.next = n;
                continue :outer;
            }
        }
    }
}

pub fn handleUartInterrupt(state: *interrupts.RegisterState) void {
    scheduler.preemptDisable();
    defer scheduler.preemptEnable();

    _ = state;

    const uart_status = get32(.AUX_MU_IIR_REG);
    var config = get32(.AUX_MU_IER_REG);

    if ((uart_status & (1 << 1)) != 0) {
        // Disable interrupts for this until the next time
        // we need them for a wake-up; without this, the interrupt
        // handler will stay asserted.
        config &= ~@as(u32, 1 << 1);
    }

    put32(.AUX_MU_IER_REG, config);
    uart_task.wake();
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    scheduler.preemptDisable();
    defer scheduler.preemptEnable();

    _ = args;
    _ = scope;
    _ = message_level;

    // var buf: [256]u8 = undefined;
    // const output = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch {
    //     panic("Log failed, message too long", null);
    // };

    // if (output.len == 0) return;

    uartSpinWrite(fmt ++ "\n");

    // const q_tail = &queue_tail;

    // var node = Node{ .task = scheduler.Task.current(), .str = output };
    // var tail = @atomicLoad(*Node, q_tail, .SeqCst);
    // while (@cmpxchgWeak(*Node, q_tail, tail, &node, .SeqCst, .SeqCst)) |new| {
    //     tail = new;
    // }

    // @atomicStore(?*const Node, &tail.next, &node, .SeqCst);

    // uart_task.wake();
    // Task.switchToAndSleep(uart_task);
}

pub fn uartSpinWrite(str: []const u8) void {
    for (str) |c| {
        if (c == '\n') {
            while ((get32(.AUX_MU_LSR_REG) & 0x20) == 0) {}

            put32(.AUX_MU_IO_REG, '\r');
        }

        // Wait for UART to become ready to transmit.
        while ((get32(.AUX_MU_LSR_REG) & 0x20) == 0) {}

        put32(.AUX_MU_IO_REG, c);
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);

    _ = error_return_trace;

    scheduler.preemptDisable();

    put32(.AUX_MU_CNTL_REG, 0); //Disable auto flow control and disable receiver and transmitter (for now)
    put32(.AUX_MU_IER_REG, 0); //Disable receive and transmit interrupts
    put32(.AUX_MU_CNTL_REG, 3); //Finally, enable transmitter and receiver

    uartSpinWrite("PANICKED: ");
    uartSpinWrite(msg);
    uartSpinWrite("\n");

    while (true) {
        asm volatile ("nop");
    }
}

pub const MBOX = struct {
    pub const REQUEST: u32 = 0;
    pub const TAG_LAST: u32 = 0;
    pub const RESPONSE: u32 = 0x80000000;
    pub const FULL: u32 = 0x80000000;
    pub const EMPTY: u32 = 0x40000000;

    pub const CH_PROP = 8;

    pub const BUS_ADDRESS_MASK = ~@as(u32, 0xC0000000);

    var mbox_: [36]u32 align(16) = undefined;
    pub const mbox: *align(16) volatile [36]u32 = &mbox_;

    pub fn spinCall(call: u4) bool {
        const mask = ~@as(u32, 0xF);
        const r = @intCast(u32, mem.physicalAddress(mbox) & mask) | call;

        while (get32(.MBOX_STATUS) & MBOX.FULL != 0) {
            asm volatile ("nop");
        }

        put32(.MBOX_WRITE, r);

        while (true) {
            while (get32(.MBOX_STATUS) & MBOX.EMPTY != 0) {
                asm volatile ("nop");
            }

            if (r == get32(.MBOX_READ))
                return mbox[1] == MBOX.RESPONSE;
        }
    }
};
