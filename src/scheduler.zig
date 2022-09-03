// Tasks:
// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/docs/lesson04/rpi-os.md
const os = @import("root");
const std = @import("std");

const memory = os.memory;
const interrupts = os.interrupts;

const TASK_ZOMBIE: u64 = 0;
const TASK_RUNNING: u64 = 1;

const CpuContext = extern struct {
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
    fp: u64,
    sp: u64,
    pc: u64,
};

extern fn ret_from_fork() void;
extern fn cpu_switch_to(prev: *Task, next: *Task) callconv(.C) void;

pub const Task = extern struct {
    registers: CpuContext,
    state: u64,
    counter: u64,
    priority: u64,
    preempt_count: u64,

    pub fn init(task_fn: fn (arg: u64) callconv(.C) void, arg: u64) !void {
        preemptDisable();

        const task_bytes = try memory.allocPages(1, false);
        errdefer memory.releasePages(task_bytes.ptr, 1);

        const task = @ptrCast(*Task, &task_bytes[0]);
        task.state = TASK_RUNNING;
        task.preempt_count = 1; // disable preemtion until schedule_tail
        task.priority = current.priority;
        task.counter = task.priority;

        task.registers.x19 = @ptrToInt(task_fn);
        task.registers.x20 = arg;
        task.registers.pc = @ptrToInt(ret_from_fork);
        task.registers.sp = @ptrToInt(task_bytes.ptr + 4096);

        try tasks.append(task);

        preemptEnable();
    }
};

var tasks: std.BoundedArray(?*Task, 256) = .{};
var current: *Task = &init_task;
var init_task: Task = .{
    .state = TASK_RUNNING,
    .counter = 0,
    .priority = 1,
    .preempt_count = 0,

    .registers = .{
        .x19 = 0,
        .x20 = 0,
        .x21 = 0,
        .x22 = 0,
        .x23 = 0,
        .x24 = 0,
        .x25 = 0,
        .x26 = 0,
        .x27 = 0,
        .x28 = 0,
        .fp = 0,
        .sp = 0,
        .pc = 0,
    },
};

pub fn preemptEnable() void {
    current.preempt_count -= 1;
}

pub fn preemptDisable() void {
    current.preempt_count += 1;
}

export fn schedule_tail() callconv(.C) void {
    preemptEnable();
}

pub fn schedule() void {
    current.counter = 0;
    scheduleImpl();
}

fn scheduleImpl() void {
    preemptDisable();

    const task: *Task = task: {
        while (true) {
            var count: u64 = 0;
            var next: ?*Task = null;

            for (tasks.slice()) |p| {
                const task = p orelse continue;

                if (task.state == TASK_RUNNING and task.counter > count) {
                    count = task.counter;
                    next = task;
                }
            }

            if (next) |task| break :task task;

            for (tasks.slice()) |p| {
                const task = p orelse continue;

                task.counter = (task.counter >> 1) + task.priority;
            }
        }

        unreachable;
    };

    switchTo(task);
    preemptEnable();
}

pub fn timerTick() void {
    current.counter -|= 1;

    if (current.counter > 0 or current.preempt_count > 0) {
        return;
    }

    current.counter = 0;

    interrupts.enableIrqs();

    scheduleImpl();

    interrupts.disableIrqs();
}

pub fn switchTo(next: *Task) callconv(.C) void {
    if (current == next) return;

    const prev = current;
    current = next;

    cpu_switch_to(prev, next);
}

comptime {
    asm ("" ++
            \\.global cpu_switch_to
            \\cpu_switch_to:
            \\
        ++ std.fmt.comptimePrint("mov  x10, {}\n", .{0}) ++
            \\  add  x8, x0, x10
            \\  mov  x9, sp
            \\  stp  x19, x20, [x8], #16 // store callee-saved registers
            \\  stp  x21, x22, [x8], #16
            \\  stp  x23, x24, [x8], #16
            \\  stp  x25, x26, [x8], #16
            \\  stp  x27, x28, [x8], #16
            \\  stp  x29, x9, [x8], #16
            \\  str  x30, [x8]
            \\  add  x8, x1, x10
            \\  ldp  x19, x20, [x8], #16 // restore callee-saved registers
            \\  ldp  x21, x22, [x8], #16
            \\  ldp  x23, x24, [x8], #16
            \\  ldp  x25, x26, [x8], #16
            \\  ldp  x27, x28, [x8], #16
            \\  ldp  x29, x9, [x8], #16
            \\  ldr  x30, [x8]
            \\  mov  sp, x9
            \\  ret
            \\
            \\.globl ret_from_fork
            \\ret_from_fork:
            \\  bl   schedule_tail
            \\  mov  x0, x20
            \\  blr  x19 //should never return
            \\
    );
}

pub fn init() void {
    tasks.append(current) catch unreachable;
}
