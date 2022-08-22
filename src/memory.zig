pub const size = 1024 * 1024 * 1024;

// PLAN:
//
// 1. Create mapping offline for 1GB, as array, at comptime
// 2. store mapping in data section
// 3. Write asm for setting mapping and then jumping to correct location
// 4. Profit?

export var kernel_memory_map align(4096) = map: {
    var map = [1]u64{0} ** (4096 / 8 * 3);
    break :map map;
};
