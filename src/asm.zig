pub fn delay(count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn readSp() usize {
    return asm volatile ("mov %[a], sp"
        : [a] "=r" (-> usize),
    );
}

pub fn mrs(comptime name: []const u8) usize {
    return asm ("mrs %[reg], " ++ name
        : [reg] "=r" (-> usize),
    );
}
