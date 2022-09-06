// Tasks:
// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/docs/lesson04/rpi-os.md
const os = @import("root");
const std = @import("std");

const memory = os.memory;
const interrupts = os.interrupts;

const TaskState = enum(u8) {
    running,
    waiting,
};

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

pub const Task = struct {
    // TODO: eventually make IDs u64 or something, idk
    id: u8,

    const Self = @This();

    pub fn init(task_fn: fn (arg: u64) callconv(.C) void, arg: u64) !Self {
        preemptDisable();
        defer preemptEnable();

        const task_bytes = try memory.allocPages(1, false);
        errdefer memory.releasePages(task_bytes.ptr, 1);

        const task = @ptrCast(*TaskInfo, task_bytes.ptr);
        task.state = .running;
        task.id = @intCast(u8, tasks.len);
        task.preempt_count = 1; // disable preemtion until schedule_tail
        task.priority = current_task.priority;
        task.counter = task.priority;

        task.registers.x19 = @ptrToInt(task_fn);
        task.registers.x20 = arg;
        task.registers.pc = @ptrToInt(ret_from_fork);
        task.registers.sp = @ptrToInt(task_bytes.ptr + 4096);

        try tasks.append(task);

        return Self{
            .id = task.id,
        };
    }

    pub fn current() Self {
        return Self{
            .id = current_task.id,
        };
    }

    pub fn wake(self: Self) void {
        tasks.slice()[self.id].state = .running;
    }

    pub fn switchToAndSleep(self: Self) void {
        if (self.id == current_task.id) return;

        preemptDisable();

        tasks.slice()[current_task.id].status = .waiting;
        tasks.slice()[self.id].switchTo();

        preemptEnable();
    }

    pub fn switchTo(self: Self) void {
        if (self.id == current_task.id) return;

        preemptDisable();

        tasks.slice()[self.id].switchTo();

        preemptEnable();
    }
};

const TaskInfo = extern struct {
    registers: CpuContext,
    state: TaskState,
    id: u8,
    padding_1: u16 = 0,
    preempt_count: u32,
    counter: u64,
    priority: u64,

    // This requires preempts to already be disabled
    fn switchToUnsafe(next: *TaskInfo) callconv(.C) void {
        if (current_task == next) return;

        const prev = current_task;
        current_task = next;

        cpu_switch_to(prev, next);
    }
};

var tasks: std.BoundedArray(?*TaskInfo, 256) = .{};
var current_task = &init_task;
var init_task = TaskInfo{
    .state = .running,
    .id = 0,
    .counter = 0,
    .priority = 10,
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

pub fn init() void {
    tasks.append(current_task) catch unreachable;
}

pub fn preemptEnable() void {
    current_task.preempt_count -= 1;
}

pub fn preemptDisable() void {
    current_task.preempt_count += 1;
}

pub fn schedule() void {
    current_task.counter = 0;
    scheduleImpl();
}

fn scheduleImpl() void {
    preemptDisable();

    const task = task: {
        while (true) {
            var count: u64 = 0;
            var next: ?*TaskInfo = null;

            for (tasks.slice()) |p| {
                const task = p orelse continue;

                if (task.state == .running and task.counter > count) {
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

    task.switchToUnsafe();

    preemptEnable();
}

pub fn timerTick() void {
    current_task.counter -|= 1;

    if (current_task.counter > 0 or current_task.preempt_count > 0) {
        return;
    }

    current_task.counter = 0;

    interrupts.enableIrqs();

    scheduleImpl();

    interrupts.disableIrqs();
}

extern fn ret_from_fork() void;
extern fn cpu_switch_to(prev: *TaskInfo, next: *TaskInfo) callconv(.C) void;

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

export fn schedule_tail() callconv(.C) void {
    preemptEnable();
}
