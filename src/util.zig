const std = @import("std");

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const GPA = std.heap.GeneralPurposeAllocator(.{});

var initialized = false;
var gpa: GPA = undefined;

var arena: Arena = undefined;

// This initializes the global allocator
pub fn init() void {
    if (initialized) {
        return;
    }

    initialized = true;
    gpa = GPA{};
    arena = Arena.init(gpa.allocator());
}

// Global allocator
pub fn allocator() Allocator {
    if (!initialized) {
        init();
    }

    return arena.allocator();
}

// This deinitializes the global allocator
pub fn deinit() void {
    initialized = false;

    arena.deinit();
    _ = gpa.deinit();
}
