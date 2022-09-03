// Tasks:
// https://github.com/s-matyukevich/raspberry-pi-os/blob/master/docs/lesson04/rpi-os.md
const os = @import("root");
const std = @import("std");

pub const TaskStatus = State;
const State = union(enum) {
    done: void,
    running: void,
};

const TASK_RUNNING: u64 = 0;
const TASK_ZOMBIE: u64 = 1;

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
    cpu_context: CpuContext,
    state: u64,
    counter: u64,
    priority: u64,
    preempt_count: u64,
};

var tasks: std.BoundedArray(Task, 256) = .{};
var current: *Task = &tasks.buffer[0];

pub fn doSmthn(status: State, state: *u64) State {
    _ = status;
    _ = state;

    return .running;
}

pub fn init() void {
    _ = tasks.addOne() catch unreachable;
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
