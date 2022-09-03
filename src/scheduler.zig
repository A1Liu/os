// Tasks:
// Going to try to use functional GC style for this, because stack-ful coroutines
// scare me.
// Tasks are implemented as pieces of state + some code that operates on it.
//
// Everything still needs to be interrupt-safe, but ideally we don't really
// use a stack for the task.

pub const TaskStatus = State;
const State = union(enum) {
    done: void,
    running: void,
};

var a: [200]u8 = undefined;

const Task = struct {
    id: u32,
    status: State,
    update: fn (status: State, state: *anyopaque) State,
    state: *anyopaque,

    pub fn init(
        initialState: anytype,
        comptime update: fn (status: State, state: *@TypeOf(initialState)) State,
    ) @This() {
        const T = @TypeOf(initialState);

        const func = struct {
            fn func(status: State, state: *anyopaque) State {
                const ptr = @ptrCast(*T, @alignCast(@alignOf(T), state));

                return update(status, ptr);
            }
        }.func;

        const ptr = @ptrCast(*T, &a[0]);
        ptr.* = initialState;

        return .{
            .id = 0,
            .status = .running,
            .state = ptr,
            .update = func,
        };
    }
};

pub fn doSmthn(status: State, state: *u64) State {
    _ = status;
    _ = state;

    return .running;
}

pub fn init() void {
    const val: u64 = 0;
    const task = Task.init(val, doSmthn);

    _ = task;
}
