var globals_: Globals align(4096) = undefined;
pub const globals: *align(4096) Globals = &globals_;

const Globals = struct {
    padding: [4096]u8,
};

comptime {
    if (@sizeOf(Globals) != 4096) {
        @compileLog("Globals aren't the size of a single page anymore!");
    }
}
