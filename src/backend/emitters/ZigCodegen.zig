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
    try writer.print("pub const States = enum(u32) {{\n", .{});

    for (self.ir.sym_tab.items) |s| {
        if (s.type == .State) {
            try writer.print("\t{s} = {d},\n", .{ s.name, s.value });
        }
    }

    try writer.print("}};\n\n", .{});
}

fn generate_enums(self: *Self, writer: std.io.AnyWriter) !void {
    for (self.ir.enum_tab.items) |e| {
        // Find the backing type
        const sym = self.ir.sym_tab.items[e.backing_type];

        try writer.print("pub const {s} = enum({s}) {{\n", .{ e.name, sym.name });

        for (e.entries) |entry| {
            try writer.print("\t{s} = {d},\n", .{ entry.name, entry.value });
        }

        // Generate reading function
        try writer.print("\n\tpub fn read(self: *{s}, reader: Reader) !void {{\n", .{e.name});
        try writer.print("\t\tself.* = @enumFromInt(try reader.readInt({s}, .{s}));\n", .{ sym.name, @tagName(self.ir.endian) });
        try writer.print("\t}}\n\n", .{});

        // Generate writing function
        try writer.print("\tpub fn write(self: *{s}, writer: std.io.AnyWriter) !void {{\n", .{e.name});
        try writer.print("\t\ttry writer.writeInt({s}, @intFromEnum(self.*), .{s});\n", .{ sym.name, @tagName(self.ir.endian) });
        try writer.print("\t}}\n\n", .{});

        try writer.print("}};\n\n", .{});
    }
}

fn generate_struct_read(self: *Self, writer: std.io.AnyWriter, s: IR.Structure) !void {
    try writer.print("\n\tpub fn read(self: *{s}, reader: Reader) !void {{\n", .{s.name});

    var used: bool = false;

    for (s.entries) |e| {
        switch (e.type) {
            .Base => {
                const sym = self.ir.sym_tab.items[e.value];
                if (std.mem.eql(u8, sym.name, "u8") or std.mem.eql(u8, sym.name, "u16") or std.mem.eql(u8, sym.name, "u32") or std.mem.eql(u8, sym.name, "u64") or std.mem.eql(u8, sym.name, "i8") or std.mem.eql(u8, sym.name, "i16") or std.mem.eql(u8, sym.name, "i32") or std.mem.eql(u8, sym.name, "i64")) {
                    try writer.print("\t\tself.{s} = try reader.readInt({s}, .{s});\n", .{ e.name, sym.name, @tagName(self.ir.endian) });
                } else if (std.mem.eql(u8, sym.name, "f32")) {
                    try writer.print("\t\tself.{s} = @bitCast(try reader.readInt(u32, .{s}));\n", .{ e.name, @tagName(self.ir.endian) });
                } else if (std.mem.eql(u8, sym.name, "f64")) {
                    try writer.print("\t\tself.{s} = @bitCast(try reader.readInt(u64, .{s}));\n", .{ e.name, @tagName(self.ir.endian) });
                } else if (std.mem.eql(u8, sym.name, "bool")) {
                    try writer.print("\t\tself.{s} = try reader.readByte() != 0;\n", .{e.name});
                }

                used = true;
            },

            .User => {
                try writer.print("\t\ttry self.{s}.read();\n", .{e.name});

                used = true;
            },

            .FixedArray => {
                try writer.print("\t\tself.{s}.len = {};\n", .{ e.name, e.extra });
                try writer.print("\t\tself.{s}.ptr = reader.context.buffer.ptr + reader.context.pos;\n", .{e.name});
                try writer.print("\t\ttry reader.skipBytes({}, .{{}});\n", .{e.extra});

                used = true;
            },

            .VarArray => {
                return error.VarArrayUnimplemented;
            },
        }
    }

    if (!used) {
        try writer.print("\t\t_ = self;\n\t\t_ = reader;\n", .{});
    }

    try writer.print("\t}}\n\n", .{});
}

fn generate_struct_write(self: *Self, writer: std.io.AnyWriter, s: IR.Structure) !void {
    try writer.print("\tpub fn write(self: *{s}, writer: std.io.AnyWriter) !void {{\n", .{s.name});

    var used: bool = false;

    for (s.entries) |e| {
        switch (e.type) {
            .Base => {
                const sym = self.ir.sym_tab.items[e.value];
                if (std.mem.eql(u8, sym.name, "u8") or std.mem.eql(u8, sym.name, "u16") or std.mem.eql(u8, sym.name, "u32") or std.mem.eql(u8, sym.name, "u64") or std.mem.eql(u8, sym.name, "i8") or std.mem.eql(u8, sym.name, "i16") or std.mem.eql(u8, sym.name, "i32") or std.mem.eql(u8, sym.name, "i64")) {
                    try writer.print("\t\ttry writer.writeInt({s}, self.{s}, .{s});\n", .{ sym.name, e.name, @tagName(self.ir.endian) });
                } else if (std.mem.eql(u8, sym.name, "f32")) {
                    try writer.print("\t\ttry writer.writeInt(@as(u32, @bitCast(self.{s})), .{s});\n", .{ e.name, @tagName(self.ir.endian) });
                } else if (std.mem.eql(u8, sym.name, "f64")) {
                    try writer.print("\t\ttry writer.writeInt(@as(u64, @bitCast(self.{s})), .{s});\n", .{ e.name, @tagName(self.ir.endian) });
                } else if (std.mem.eql(u8, sym.name, "bool")) {
                    try writer.print("\t\ttry writer.writeByte(self.{s} ? 1 : 0);\n", .{e.name});
                }
                used = true;
            },

            .User => {
                try writer.print("\t\ttry self.{s}.write();\n", .{e.name});
                used = true;
            },

            .FixedArray => {
                try writer.print("\t\ttry writer.writeAll(self.{s});\n", .{e.name});
                used = true;
            },

            .VarArray => {
                return error.VarArrayUnimplemented;
            },
        }
    }

    if (!used) {
        try writer.print("\t\t_ = self;\n\t\t_ = writer;\n", .{});
    }

    try writer.print("\t}}\n\n", .{});
}

fn generate_structs(self: *Self, writer: std.io.AnyWriter) !void {
    for (self.ir.struct_tab.items) |s| {
        try writer.print("pub const {s} = struct {{\n", .{s.name});

        for (s.entries) |e| {
            switch (e.type) {
                .Base, .User => {
                    const f_type = self.ir.sym_tab.items[e.value].name;
                    try writer.print("\t{s}: {s},\n", .{ e.name, f_type });
                },

                .FixedArray, .VarArray => {
                    const f_type = self.ir.sym_tab.items[e.value].name;
                    try writer.print("\t{s}: []{s},\n", .{ e.name, f_type });
                },
            }
        }

        try generate_struct_read(self, writer, s);
        try generate_struct_write(self, writer, s);

        try writer.print("}};\n\n", .{});
    }
}

fn generate_handles_struct(self: *Self, writer: std.io.AnyWriter) !void {
    try writer.print("pub const Handles = struct {{\n", .{});

    for (self.ir.struct_tab.items) |s| {
        if (s.event) {
            try writer.print("\thandle_{s}: ?*const fn (ctx: *anyopaque, event: {s}) anyerror!void = null,\n", .{ s.name, s.name });
        }
    }

    try writer.print("}};\n\n", .{});
}

pub fn generate_handler_function(self: *Self, writer: std.io.AnyWriter) !void {
    try writer.print("\tpub fn handle_packet(self: *Protocol, buffer: []u8, id: u8) anyerror!void {{\n", .{});

    try writer.print("\t\tvar fbs = std.io.fixedBufferStream(buffer);\n", .{});
    try writer.print("\t\tconst reader = fbs.reader();\n", .{});

    try writer.print("\n\t\tif (self.role == .Server) {{", .{});
    try writer.print("\n\t\t\tswitch (self.state) {{", .{});

    for (self.ir.sym_tab.items) |s| {
        if (s.type == .State) {
            try writer.print("\n\t\t\t\t.{s} => {{\n", .{s.name});
            try writer.print("\t\t\t\t\tswitch (id) {{\n", .{});

            for (self.ir.struct_tab.items) |st| {
                if (!st.event)
                    continue;

                if (std.mem.eql(u8, self.ir.sym_tab.items[st.state_id.?].name, s.name) and (st.direction.? == .Client or st.direction.? == .Both)) {
                    try writer.print("\t\t\t\t\t\t{} => {{\n", .{st.event_id.?});
                    try writer.print("\t\t\t\t\t\t\tvar event: {s} = undefined;\n", .{st.name});
                    try writer.print("\t\t\t\t\t\t\ttry event.read(reader);\n", .{});
                    try writer.print("\t\t\t\t\t\t\tif (self.handle.handle_{s}) |pfn|\n", .{st.name});
                    try writer.print("\t\t\t\t\t\t\t\ttry pfn(self.context, event);\n", .{});
                    try writer.print("\t\t\t\t\t\t}},\n", .{});
                }
            }

            try writer.print("\t\t\t\t\t\telse => {{}},\n", .{});

            try writer.print("\t\t\t\t\t}}\n", .{});
            try writer.print("\t\t\t\t}},", .{});
        }
    }

    try writer.print("\n\t\t\t}}\n", .{});

    try writer.print("\t\t}} else if (self.role == .Client) {{", .{});
    try writer.print("\n\t\t\tswitch (self.state) {{", .{});

    for (self.ir.sym_tab.items) |s| {
        if (s.type == .State) {
            try writer.print("\n\t\t\t\t.{s} => {{\n", .{s.name});
            try writer.print("\t\t\t\t\tswitch (id) {{\n", .{});

            for (self.ir.struct_tab.items) |st| {
                if (!st.event)
                    continue;

                if (std.mem.eql(u8, self.ir.sym_tab.items[st.state_id.?].name, s.name) and (st.direction.? == .Server or st.direction.? == .Both)) {
                    try writer.print("\t\t\t\t\t\t{} => {{\n", .{st.event_id.?});
                    try writer.print("\t\t\t\t\t\t\tvar event: {s} = undefined;\n", .{st.name});
                    try writer.print("\t\t\t\t\t\t\ttry event.read(reader);\n", .{});
                    try writer.print("\t\t\t\t\t\t\tif (self.handle.handle_{s}) |pfn|\n", .{st.name});
                    try writer.print("\t\t\t\t\t\t\t\ttry pfn(self.context, event);\n", .{});
                    try writer.print("\t\t\t\t\t\t}},\n", .{});
                }
            }

            try writer.print("\t\t\t\t\t\telse => {{}},\n", .{});

            try writer.print("\t\t\t\t\t}}\n", .{});
            try writer.print("\t\t\t\t}},", .{});
        }
    }

    try writer.print("\n\t\t\t}}\n", .{});

    try writer.print("\t\t}}\n", .{});
    try writer.print("\t}}\n", .{});
}

pub fn generate_code(self: *Self, filename: []const u8) !void {
    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const file_writer = file.writer();
    var buffered_writer = std.io.bufferedWriter(file_writer);
    defer buffered_writer.flush() catch unreachable;

    const writer = buffered_writer.writer().any();

    try writer.print("const std = @import(\"std\");\n\n", .{});

    try writer.print("pub const Reader = std.io.FixedBufferStream([]u8).Reader;\n\n", .{});

    try writer.print("pub const Roles = enum(u32) {{\n", .{});
    try writer.print("\tServer = 0,\n", .{});
    try writer.print("\tClient = 1,\n", .{});
    try writer.print("}};\n\n", .{});

    try self.generate_states(writer);
    try self.generate_enums(writer);
    try self.generate_structs(writer);

    try self.generate_handles_struct(writer);

    try writer.print("pub const Protocol = struct {{\n", .{});

    try writer.print("\trole: Roles,\n", .{});
    try writer.print("\tstate: States,\n", .{});
    try writer.print("\thandle: Handles,\n", .{});
    try writer.print("\tcontext: *anyopaque,\n", .{});

    try writer.print("\n\tpub fn init(role: Roles, state: States, context: *anyopaque) Protocol {{", .{});
    try writer.print("\n\t\treturn .{{.role = role, .state = state, .handle = .{{}}, .context = context}};\n", .{});
    try writer.print("\t}}\n\n", .{});

    try self.generate_handler_function(writer);

    try writer.print("}};\n", .{});
}
