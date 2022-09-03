// Tasks:
// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/docs/lesson04/rpi-os.md
const os = @import("root");
const std = @import("std");

const memory = os.memory;

pub const TaskStatus = State;
const State = union(enum) {
    done: void,
    running: void,
};

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

const Task = extern struct {
    registers: CpuContext,
    state: u64,
    counter: u64,
    priority: u64,
    preempt_count: u64,

    pub fn init(task_fn: fn (arg: u64) callconv(.C) void, arg: u64) !*@This() {
        preemptDisable();

        const task_bytes = try memory.allocPages(1, false);
        errdefer memory.releasePages(task_bytes.ptr, 1);

        const task = @ptrCast(*Task, &task_bytes[0]);
        task.state = TASK_RUNNING;
        task.preempt_count = 1; //disable preemtion until schedule_tail
        task.priority = current.priority;
        task.counter = task.priority;

        task.registers.x19 = @bitCast(u64, task_fn);
        task.registers.x20 = arg;
        task.registers.pc = @bitCast(u64, ret_from_fork);
        task.registers.sp = @bitCast(u64, task_bytes.ptr + 4096);
        try tasks.append(task);
    }
};

var tasks: std.BoundedArray(*Task, 256) = .{};
var current: *Task = &init_task;
var init_task: Task = .{
    .state = 0,
    .counter = 0,
    .priority = 0,
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

pub fn scheduleFromTask() void {}

pub fn schedule() void {
    preemptDisable();
    const task: *Task = task: {
        while (true) {
            var count: u64 = 0;
            var next: ?*Task = null;

            for (tasks.slice()) |task| {
                if (task.state == TASK_RUNNING and task.counter > count) {
                    count = task.counter;
                    next = task;
                }
            }

            if (next) |task| {
                break :task task;
            }

            for (tasks.slice()) |task| {
                if (task.state != TASK_RUNNING) continue;

                task.counter = (task.counter >> 1) + task.priority;
            }
        }

        unreachable;
    };

    switchTo(task);
    preemptEnable();
}

pub fn switchTo(task: *Task) void {
    _ = task;
}

pub fn doSmthn(status: State, state: *u64) State {
    _ = status;
    _ = state;

    return .running;
}

pub fn init() void {
    tasks.append(current) catch unreachable;

    if (current.state == 1) {
        schedule();
    }

    // const val: u64 = 0;
    // const task = Task.init(val, doSmthn);

}

// pub const Task = struct {
//     id: u32,
//     status: State,
//     update: fn (status: State, state: *anyopaque) State,
//     state: *anyopaque,
//
//     pub fn init(
//         initialState: anytype,
//         comptime update: fn (status: State, state: *@TypeOf(initialState)) State,
//     ) @This() {
//         const T = @TypeOf(initialState);
//
//         const func = struct {
//             fn func(status: State, state: *anyopaque) State {
//                 const ptr = @ptrCast(*T, @alignCast(@alignOf(T), state));
//
//                 return update(status, ptr);
//             }
//         }.func;
//
//         const ptr = @ptrCast(*T, &a[0]);
//         ptr.* = initialState;
//
//         return .{
//             .id = 0,
//             .status = .running,
//             .state = ptr,
//             .update = func,
//         };
//     }
// };
