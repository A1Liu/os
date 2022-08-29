// Tasks:
// Going to try to use functional GC style for this, because stack-ful coroutines
// scare me.
// Tasks are implemented as pieces of state + some code that operates on it.
// The code either returns a new state pointer or returns done or something idk.
// It should always operate atomically, either by returning a new state or by
// atomically mutating current state.
//
// Should have a version for synchronous-style and maybe also one for async? idk
const TaskState = enum {
    running,
    waiting,
};

const Task = struct {
    interruptible: bool,
    id: u32,
    extra_info: u32,
    update: *fn (state: u64) callconv(.C) u64,
    state: u64,
};
