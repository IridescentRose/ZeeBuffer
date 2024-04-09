const std = @import("std");
const util = @import("util.zig");
const IR = @import("IR.zig");
const ZigGenerator = @import("backend/zig.zig");

pub const GeneratorType = enum(u8) {
    Zig,
};

pub const Generator = struct {
    context: *anyopaque,
    table: VTable,

    pub const VTable = struct {
        init: *const fn (context: *anyopaque, ir: IR) anyerror!void,
        write_header: *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void,
        write_footer: *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void,

        write_struct: *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void,
        write_enum: *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void,
        write_state: *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void,

        write_handle_table: *const fn (context: *anyopaque, writer: std.io.AnyWriter) anyerror!void,
    };

    pub fn init(self: Generator, ir: IR) anyerror!void {
        return self.table.init(self.context, ir);
    }

    pub fn write_header(self: Generator, writer: std.io.AnyWriter) anyerror!void {
        return self.table.write_header(self.context, writer);
    }

    pub fn write_footer(self: Generator, writer: std.io.AnyWriter) anyerror!void {
        return self.table.write_footer(self.context, writer);
    }

    pub fn write_struct(self: Generator, writer: std.io.AnyWriter) anyerror!void {
        return self.table.write_struct(self.context, writer);
    }

    pub fn write_enum(self: Generator, writer: std.io.AnyWriter) anyerror!void {
        return self.table.write_enum(self.context, writer);
    }

    pub fn write_state(self: Generator, writer: std.io.AnyWriter) anyerror!void {
        return self.table.write_state(self.context, writer);
    }

    pub fn write_handle_table(self: Generator, writer: std.io.AnyWriter) anyerror!void {
        return self.table.write_handle_table(self.context, writer);
    }
};

fn get_generator(format: GeneratorType) !Generator {
    return switch (format) {
        GeneratorType.Zig => blk: {
            var context = try util.allocator().create(ZigGenerator);
            break :blk context.generator();
        },
    };
}

pub fn generate(format: GeneratorType, ir: IR, writer: std.io.AnyWriter) !void {
    var generator = try get_generator(format);
    try generator.init(ir);

    try generator.write_header(writer);
    try generator.write_state(writer);
    try generator.write_enum(writer);
    try generator.write_struct(writer);
    try generator.write_handle_table(writer);
    try generator.write_footer(writer);
}
