const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const GPA = std.heap.GeneralPurposeAllocator(.{});

// Is initialized?
var initialized = false;

// Allocators
var gpa: GPA = undefined;
var arena: Arena = undefined;

/// Creates the global allocator
pub fn init() void {
    assert(!initialized);

    initialized = true;
    gpa = GPA{};
    arena = Arena.init(gpa.allocator());
}

/// Deinitializes the global allocator
pub fn deinit() void {
    assert(initialized);

    initialized = false;
    arena.deinit();
    _ = gpa.deinit();
}

pub fn allocator() Allocator {
    assert(initialized);

    return arena.allocator();
}
