const std = @import("std");
const IR = @import("../../IR.zig");

const Self = @This();

ir: *const IR,

pub fn init(ir: *const IR) Self {
    return Self{
        .ir = ir,
    };
}

pub fn generate_code(self: *Self, filename: []const u8) !void {
    _ = self;
    _ = filename;

    std.debug.print("C is not yet supported!\n", .{});
}
