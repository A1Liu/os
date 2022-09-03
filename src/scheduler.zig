// Tasks:
// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/docs/lesson04/rpi-os.md
const os = @import("root");
const std = @import("std");

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

const Task = extern struct {
    registers: CpuContext,
    state: u64,
    counter: u64,
    priority: u64,
    preempt_count: u64,
};

var tasks: std.BoundedArray(Task, 256) = .{};
var current: *Task = undefined;

pub fn doSmthn(status: State, state: *u64) State {
    _ = status;
    _ = state;

    return .running;
}

pub fn preemptEnable() void {
    current.preempt_count += 1;
}

pub fn preemptDisable() void {
    current.preempt_count -= 1;
}

pub fn scheduleFromTask() void {}

pub fn schedule() void {
    preemptDisable();
    const task: *Task = task: {
        while (true) {
            var count: u64 = 0;
            var next: ?*Task = null;

            for (tasks.slice()) |*task| {
                if (task.state == TASK_RUNNING and task.counter > count) {
                    count = task.counter;
                    next = task;
                }
            }

            if (next) |task| {
                break :task task;
            }

            for (tasks.slice()) |*task| {
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

pub fn init() void {
    current = tasks.addOne() catch unreachable;

    current.registers.x19 = 0;
    current.registers.x20 = 0;
    current.registers.x21 = 0;
    current.registers.x22 = 0;
    current.registers.x23 = 0;
    current.registers.x24 = 0;
    current.registers.x25 = 0;
    current.registers.x26 = 0;
    current.registers.x27 = 0;
    current.registers.x28 = 0;
    current.registers.fp = 0;
    current.registers.sp = 0;
    current.registers.pc = 0;

    current.state = 0;
    current.counter = 0;
    current.priority = 0;
    current.preempt_count = 0;

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
