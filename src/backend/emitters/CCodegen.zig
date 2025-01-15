const std = @import("std");
const IR = @import("../../IR.zig");

const Self = @This();

ir: *const IR,

pub fn init(ir: *const IR) Self {
    return Self{
        .ir = ir,
    };
}

fn generate_states(self: *Self, writer: std.io.AnyWriter) !void {
    try writer.print("enum ZB_States {{\n", .{});

    var first = true;

    for (self.ir.sym_tab.items) |s| {
        if (s.type == .State) {
            if (!first) {
                try writer.print(",\n", .{});
            }
            first = false;

            try writer.print("\tZB_State_{s} = {d}", .{ s.name, s.value });
        }
    }

    try writer.print("\n}};\n\n", .{});
}

pub fn generate_code(self: *Self, filename: []const u8) !void {
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const file_writer = file.writer();
    var buffered_writer = std.io.bufferedWriter(file_writer);
    defer buffered_writer.flush() catch unreachable;

    const writer = buffered_writer.writer().any();

    try writer.print("#pragma once\n\n", .{});

    try writer.print("enum ZBRole {{\n", .{});
    try writer.print("\tZB_Role_Server = 0,\n", .{});
    try writer.print("\tZB_Role_Client = 1\n", .{});
    try writer.print("}};\n\n", .{});

    try self.generate_states(writer);
}
