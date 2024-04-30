const std = @import("std");
const util = @import("../util.zig");
const IR = @import("../IR.zig");
const Generator = @import("../CodeGen.zig").Generator;

const StateFields = struct {
    name: []const u8,
    value: u16,
};

const StructFields = struct {
    name: []const u8,
    value: u16,
    oname: []const u8,
};

const StateStructPair = struct {
    state: StateFields,
    entries: []StructFields,
};

ir: IR,
state_fields: std.ArrayList(StateFields),
state_struct_array: std.ArrayList(StateStructPair),

const Self = @This();

fn coerce(ctx: *anyopaque) *Self {
    return @ptrCast(@alignCast(ctx));
}

pub fn generator(self: *Self) Generator {
    return Generator{
        .context = self,
        .table = .{
            .init = init,
            .write_header = write_header,
            .write_footer = write_footer,
            .write_struct = write_struct,
            .write_enum = write_enum,
            .write_state = write_state,
            .write_handle_table = write_handle_table,
        },
    };
}

fn init(ctx: *anyopaque, ir: IR) anyerror!void {
    var self = coerce(ctx);
    self.ir = ir;
}

fn write_header(ctx: *anyopaque, writer: std.io.AnyWriter) !void {
    _ = ctx;
    try writer.print("const std = @import(\"std\");\n\n", .{});
}

fn write_state(ctx: *anyopaque, writer: std.io.AnyWriter) !void {
    const self = coerce(ctx);
    self.state_fields = std.ArrayList(StateFields).init(util.allocator());

    try writer.print("pub const ProtoState = enum(u16) {{\n", .{});
    for (self.ir.symbol_table.entries.items) |sym| {
        if (sym.type == .State) {
            try writer.print("    {s} = {},\n", .{ sym.name, sym.value });
            try self.state_fields.append(.{ .name = sym.name, .value = @intCast(sym.value) });
        }
    }
    try writer.print("}};\n\n", .{});
}
fn write_struct_deinit(self: *Self, writer: std.io.AnyWriter, e: IR.Structure, struct_name: []const u8) !void {
    _ = self;
    try writer.print("\n    pub fn deinit(self: *{s}, allocator: std.mem.Allocator) void {{\n", .{struct_name});

    var allocator_used: bool = false;

    for (e.entries) |entry| {
        switch (entry.type.type) {
            .User => {
                try writer.print("        self.{s}.deinit(allocator);\n", .{entry.name});
                allocator_used = true;
            },
            .VarArray => {
                try writer.print("        allocator.free(self.{s});\n", .{entry.name});
                allocator_used = true;
            },
            else => {},
        }
    }

    if (!allocator_used) {
        try writer.print("        _ = self;\n", .{});
        try writer.print("        _ = allocator;\n", .{});
    }
    try writer.print("    }}\n", .{});
}

fn write_struct_read(self: *Self, writer: std.io.AnyWriter, e: IR.Structure, struct_name: []const u8) !void {
    const endian_string = if (self.ir.endian == .Big) ".big" else ".little";

    var start: usize = 0;
    if (!e.flag.packet) {
        try writer.print("\n    pub fn read(self: *{s}, reader: std.io.AnyReader, allocator: std.mem.Allocator) !void {{\n", .{struct_name});
    } else {
        try writer.print("\n    pub fn read(self: *{s}, reader: std.io.AnyReader, allocator: std.mem.Allocator, protocol: *Protocol) !void {{\n", .{struct_name});
        if (std.mem.eql(u8, e.entries[0].name, "len")) {
            start = 1;
        }
    }

    var allocator_used: bool = false;
    for (e.entries[start..]) |entry| {
        switch (entry.type.type) {
            .Base => {
                const base = self.ir.symbol_table.entries.items[entry.type.value].name;

                if (std.mem.eql(u8, base, "f32")) {
                    try writer.print("        self.{s} = @bitCast(try reader.readInt(u32, {s}));\n", .{ entry.name, endian_string });
                } else if (std.mem.eql(u8, base, "f64")) {
                    try writer.print("        self.{s} = @bitCast(try reader.readInt(u64, {s}));\n", .{ entry.name, endian_string });
                } else if (std.mem.eql(u8, base, "VarInt")) {
                    try writer.print("        self.{s} = blk: {{ var value : usize = 0; var b : usize = try reader.readByte(); while(b & 0x80 != 0) {{value |= (b & 0x7F) << 7; value <<= 7; b = try reader.readByte();}} value |= b; break :blk value; }};\n", .{entry.name});
                } else if (std.mem.eql(u8, base, "bool")) {
                    try writer.print("        self.{s} = try reader.readByte() == 0;\n", .{entry.name});
                } else {
                    try writer.print("        self.{s} = try reader.readInt({s}, {s});\n", .{ entry.name, base, endian_string });
                }
            },
            .User => {
                try writer.print("        try self.{s}.read(reader, allocator);\n", .{entry.name});
                allocator_used = true;
            },
            .FixedArray => {
                try writer.print("        for(&self.{s}) |*e| {{\n", .{entry.name});
                const base = self.ir.source.token_text_idx(entry.type.extra);

                for (self.ir.symbol_table.entries.items) |i| {
                    if (std.mem.eql(u8, base, i.name)) {
                        switch (i.type) {
                            .BaseType => {
                                if (std.mem.eql(u8, base, "f32")) {
                                    try writer.print("            e.* = @bitCast(try reader.readInt(u32, {s}));\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "f64")) {
                                    try writer.print("            e.* = @bitCast(try reader.readInt(u64, {s}));\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "VarInt")) {
                                    try writer.print("            e.* = blk: {{ var value : usize = 0; var b : usize = try reader.readByte(); while(b & 0x80 != 0) {{value |= (b & 0x7F) << 7; value <<= 7; b = try reader.readByte();}} value |= b; break :blk value; }};\n", .{});
                                } else {
                                    try writer.print("            e.* = try reader.readInt({s}, {s});\n", .{ base, endian_string });
                                }
                            },
                            .UserType => {
                                try writer.print("            try e.read(reader, allocator);\n", .{});
                                allocator_used = true;
                            },
                            else => @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues"),
                        }
                    }
                }

                try writer.print("        }}\n", .{});
            },
            .VarArray => {
                const varint = self.ir.source.token_text_idx(entry.type.value);

                for (self.ir.symbol_table.entries.items) |i| {
                    if (std.mem.eql(u8, varint, i.name)) {
                        switch (i.type) {
                            .BaseType => {
                                if (std.mem.eql(u8, varint, "VarInt")) {
                                    try writer.print("        const {s}_len = blk: {{ var value : usize = 0; var b : usize = try reader.readByte(); while(b & 0x80 != 0) {{value |= (b & 0x7F) << 7; value <<= 7; b = try reader.readByte();}} value |= b; break :blk value; }};\n", .{entry.name});
                                } else {
                                    try writer.print("        const {s}_len = try reader.readInt({s}, {s});\n", .{ entry.name, varint, endian_string });
                                }
                            },
                            else => @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues"),
                        }
                    }
                }

                const base = self.ir.source.token_text_idx(entry.type.extra);

                try writer.print("        self.{s} = try allocator.alloc({s}, {s}_len);\n", .{ entry.name, base, entry.name });
                allocator_used = true;

                try writer.print("        for(self.{s}) |*e| {{\n", .{entry.name});
                for (self.ir.symbol_table.entries.items) |i| {
                    if (std.mem.eql(u8, base, i.name)) {
                        switch (i.type) {
                            .BaseType => {
                                if (std.mem.eql(u8, base, "f32")) {
                                    try writer.print("            e.* = @bitCast(try reader.readInt(u32, {s}));\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "f64")) {
                                    try writer.print("            e.* = @bitCast(try reader.readInt(u64, {s}));\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "VarInt")) {
                                    try writer.print("            e.* = blk: {{ var value : usize = 0; var b : usize = try reader.readByte(); while(b & 0x80 != 0) {{value |= (b & 0x7F) << 7; value <<= 7; b = try reader.readByte();}} value |= b; break :blk value; }};\n", .{});
                                } else {
                                    try writer.print("            e.* = try reader.readInt({s}, {s});\n", .{ base, endian_string });
                                }
                            },
                            .UserType => {
                                try writer.print("            try e.read(reader, allocator);\n", .{});
                                allocator_used = true;
                            },
                            else => @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues"),
                        }
                    }
                }

                try writer.print("        }}\n", .{});
            },
            else => {
                if (e.flag.packet) {
                    const s = self.ir.source.token_text_idx(entry.type.value);
                    try writer.print("        try protocol.dispatch_reader(reader, allocator, self.{s});\n", .{s});
                    allocator_used = true;
                } else @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues");
            },
        }
    }
    if (!allocator_used) {
        try writer.print("        _ = allocator;\n", .{});
    }
    try writer.print("    }}\n", .{});
}

fn write_struct_write(self: *Self, writer: std.io.AnyWriter, e: IR.Structure, struct_name: []const u8) !void {
    const endian_string = if (self.ir.endian == .Big) ".big" else ".little";

    var start: usize = 0;
    if (!e.flag.packet) {
        try writer.print("\n    pub fn write(self: *{s}, writer: std.io.AnyWriter) !void {{\n", .{struct_name});
    } else {
        try writer.print("\n    pub fn write(self: *{s}, writer: std.io.AnyWriter, allocator: std.mem.Allocator, protocol: *Protocol) !void {{\n", .{struct_name});
        if (std.mem.eql(u8, e.entries[0].name, "len")) {
            start = 1;
        }
    }

    for (e.entries[start..]) |entry| {
        switch (entry.type.type) {
            .Base => {
                const base = self.ir.symbol_table.entries.items[entry.type.value].name;

                if (std.mem.eql(u8, base, "f32")) {
                    try writer.print("        try writer.writeInt(u32, @bitCast(self.{s}), {s});\n", .{ entry.name, endian_string });
                } else if (std.mem.eql(u8, base, "f64")) {
                    try writer.print("        try writer.writeInt(u64, @bitCast(self.{s}), {s});\n", .{ entry.name, endian_string });
                } else if (std.mem.eql(u8, base, "VarInt")) {
                    try writer.print("        {{ var buffer : [10]u8 = undefined; var len : usize = 0; var value = self.{s}; while((value & 0x80) != 0) {{buffer[len] = @truncate(value); len += 1; value >>= 7; }} buffer[len] = value; len += 1; try writer.writeAll(buffer[0..len]); }}\n", .{entry.name});
                } else if (std.mem.eql(u8, base, "bool")) {
                    try writer.print("        try writer.writeByte(if(self.{s}) 1 else 0);\n", .{entry.name});
                } else {
                    try writer.print("        try writer.writeInt({s}, self.{s}, {s});\n", .{ base, entry.name, endian_string });
                }
            },
            .User => {
                try writer.print("        try self.{s}.write(writer);\n", .{entry.name});
            },
            .FixedArray => {
                try writer.print("        for(&self.{s}) |*e| {{\n", .{entry.name});
                const base = self.ir.source.token_text_idx(entry.type.extra);

                for (self.ir.symbol_table.entries.items) |i| {
                    if (std.mem.eql(u8, base, i.name)) {
                        switch (i.type) {
                            .BaseType => {
                                if (std.mem.eql(u8, base, "f32")) {
                                    try writer.print("            try writer.writeInt(u32, @bitCast(e), {s});\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "f64")) {
                                    try writer.print("            try writer.writeInt(u64, @bitCast(e), {s});\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "VarInt")) {
                                    try writer.print("            var buffer : [10]u8 = undefined; var len : usize = 0; var value = e; while((value & 0x80) != 0) {{buffer[len] = @truncate(value); len += 1; value >>= 7; }} buffer[len] = value; len += 1; try writer.writeAll(buffer[0..len])\n", .{});
                                } else if (std.mem.eql(u8, base, "bool")) {
                                    try writer.print("            try writer.writeByte(if(e) 1 else 0);\n", .{});
                                } else {
                                    try writer.print("            try writer.writeInt({s}, e, {s});\n", .{ base, endian_string });
                                }
                            },
                            .UserType => {
                                try writer.print("            try e.write(writer);\n", .{});
                            },
                            else => @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues"),
                        }
                    }
                }

                try writer.print("        }}\n", .{});
            },
            .VarArray => {
                const varint = self.ir.source.token_text_idx(entry.type.value);

                for (self.ir.symbol_table.entries.items) |i| {
                    if (std.mem.eql(u8, varint, i.name)) {
                        switch (i.type) {
                            .BaseType => {
                                if (std.mem.eql(u8, varint, "VarInt")) {
                                    try writer.print("        {{ var buffer : [10]u8 = undefined; var len : usize = 0; var value = self.{s}.len; while((value & 0x80) != 0) {{buffer[len] = @truncate(value); len += 1; value >>= 7; }} buffer[len] = value; len += 1; try writer.writeAll(buffer[0..len]); }}\n", .{entry.name});
                                } else {
                                    try writer.print("        try writer.writeInt({s}, @intCast(self.{s}.len), {s});\n", .{ varint, entry.name, endian_string });
                                }
                            },
                            else => @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues"),
                        }
                    }
                }

                try writer.print("        for(&self.{s}) |*e| {{\n", .{entry.name});
                const base = self.ir.source.token_text_idx(entry.type.extra);

                for (self.ir.symbol_table.entries.items) |i| {
                    if (std.mem.eql(u8, base, i.name)) {
                        switch (i.type) {
                            .BaseType => {
                                if (std.mem.eql(u8, base, "f32")) {
                                    try writer.print("            try writer.writeInt(u32, @bitCast(e), {s});\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "f64")) {
                                    try writer.print("            try writer.writeInt(u64, @bitCast(e), {s});\n", .{endian_string});
                                } else if (std.mem.eql(u8, base, "VarInt")) {
                                    try writer.print("            {{var buffer : [10]u8 = undefined; var len : usize = 0; var value = e; while((value & 0x80) != 0) {{buffer[len] = @truncate(value); len += 1; value >>= 7; }} buffer[len] = value; len += 1; try writer.writeAll(buffer[0..len]);}}\n", .{});
                                } else if (std.mem.eql(u8, base, "bool")) {
                                    try writer.print("            try writer.writeByte(if(e) 1 else 0);\n", .{});
                                } else {
                                    try writer.print("            try writer.writeInt({s}, e, {s});\n", .{ base, endian_string });
                                }
                            },
                            .UserType => {
                                try writer.print("            try e.write(writer);\n", .{});
                            },
                            else => @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues"),
                        }
                    }
                }

                try writer.print("        }}\n", .{});
            },
            else => {
                if (e.flag.packet) {
                    const s = self.ir.source.token_text_idx(entry.type.value);

                    if (std.mem.eql(u8, e.entries[0].name, "len")) {
                        try writer.print("        var array = std.ArrayList(u8).init(allocator); defer array.deinit(); try protocol.dispatch_write(array.writer(), self.{s}, self.event);\n", .{s});
                        try writer.print("        {{var buffer : [10]u8 = undefined; var len : usize = 0; var value = array.items.len; while((value & 0x80) != 0) {{buffer[len] = @truncate(value); len += 1; value >>= 7; }} buffer[len] = value; len += 1; try writer.writeAll(buffer[0..len]);}}\n", .{});
                        try writer.print("        try writer.writeAll(array.items);\n", .{});
                    } else {
                        try writer.print("        try protocol.dispatch_write(writer, self.{s}, self.event); _ = allocator;\n", .{s});
                    }
                } else @panic("You've reached unreachable code! This is a compiler bug. Report here: https://github.com/IridescentRose/ZeeBuffer/issues");
            },
        }
    }
    try writer.print("    }}\n", .{});
}

fn write_enum_read(self: *Self, writer: std.io.AnyWriter, e: IR.Enum, struct_name: []const u8) !void {
    const endian_string = if (self.ir.endian == .Big) ".big" else ".little";

    try writer.print("\n    pub fn read(self: *{s}, reader: std.io.AnyReader, allocator: std.mem.Allocator) !void {{\n", .{struct_name});

    const base = self.ir.symbol_table.entries.items[e.type].name;
    try writer.print("        self.* = @enumFromInt(try reader.readInt({s}, {s}));\n", .{ base, endian_string });

    try writer.print("        _ = allocator;\n", .{});
    try writer.print("    }}\n", .{});
}

fn write_enum_write(self: *Self, writer: std.io.AnyWriter, e: IR.Enum, struct_name: []const u8) !void {
    const endian_string = if (self.ir.endian == .Big) ".big" else ".little";

    try writer.print("\n    pub fn write(self: {s}, writer: std.io.AnyWriter) !void {{\n", .{struct_name});

    const base = self.ir.symbol_table.entries.items[e.type].name;
    try writer.print("        try writer.writeInt({s}, @intFromEnum(self) , {s});\n", .{ base, endian_string });
    try writer.print("    }}\n", .{});
}

fn write_struct(ctx: *anyopaque, writer: std.io.AnyWriter, e: IR.Structure) !void {
    const self = coerce(ctx);
    const struct_name = try self.write_struct_name(writer, e);

    for (e.entries) |entry| {
        const eType = entry.type;

        const eTypename = switch (eType.type) {
            .Base => blk: {
                const base = self.ir.symbol_table.entries.items[eType.value].name;

                if (std.mem.eql(u8, base, "VarInt")) {
                    break :blk "usize";
                }

                break :blk base;
            },
            .User => self.ir.symbol_table.entries.items[eType.value].name,
            .Union => "*anyopaque",
            .FixedArray => blk: {
                const base = self.ir.source.token_text_idx(eType.extra);
                const size = self.ir.source.token_text_idx(eType.value);
                break :blk try std.fmt.allocPrint(util.allocator(), "[{s}]{s}", .{ size, base });
            },
            .VarArray => blk: {
                const base = self.ir.source.token_text_idx(eType.extra);
                break :blk try std.fmt.allocPrint(util.allocator(), "[]{s}", .{base});
            },
        };

        try writer.print("    {s}: {s},\n", .{ entry.name, eTypename });
    }

    // Read
    try self.write_struct_read(writer, e, struct_name);
    try self.write_struct_write(writer, e, struct_name);

    // Deinit
    try self.write_struct_deinit(writer, e, struct_name);

    try writer.print("}};\n\n", .{});
}

fn write_enum(ctx: *anyopaque, writer: std.io.AnyWriter, e: IR.Enum) !void {
    const self = coerce(ctx);

    const typename = self.ir.symbol_table.entries.items[e.type].name;

    try writer.print("pub const {s} = enum({s}) {{\n", .{ e.name, typename });

    for (e.entries) |entry| {
        try writer.print("    {s} = {},\n", .{ entry.name, entry.value });
    }

    try self.write_enum_read(writer, e, e.name);
    try self.write_enum_write(writer, e, e.name);

    try writer.print("\n    pub fn deinit(self: *{s}, allocator: std.mem.Allocator) void {{\n", .{e.name});
    try writer.print("        _ = self;\n", .{});
    try writer.print("        _ = allocator;\n", .{});
    try writer.print("    }}\n", .{});

    try writer.print("}};\n\n", .{});
}

fn write_footer(ctx: *anyopaque, writer: std.io.AnyWriter) !void {
    const self = coerce(ctx);

    try writer.print(proto_header, .{});

    for (self.ir.struct_table.entries.items) |e| {
        if (e.flag.packet and !e.flag.encrypted and !e.flag.compressed) {
            const name = e.entries[0].name;
            if (std.mem.eql(u8, "len", name)) {
                try writer.print(len_prefix, .{});
            } else if (std.mem.eql(u8, "id", name)) {
                try writer.print(id_prefix, .{});
            }
            break;
        }
    }

    // Reader Structure

    try writer.print(dispatch_read_stub, .{});
    try writer.print("        switch(self.state) {{\n", .{});

    for (self.state_struct_array.items) |struct_pair| {
        try writer.print("            .{s} => {{\n", .{struct_pair.state.name});
        try writer.print("                switch(id) {{\n", .{});

        for (struct_pair.entries) |e| {
            const my_dir = self.ir.direction == .In;
            const is_in = std.mem.containsAtLeast(u8, e.oname, 1, "In");
            const is_out = std.mem.containsAtLeast(u8, e.oname, 1, "Out") or std.mem.containsAtLeast(u8, e.oname, 1, "InOut");

            if ((!my_dir or !is_in) and (my_dir or !is_out)) continue;

            try writer.print("                    {} => {{\n", .{e.value});
            try writer.print("                        var s : {s} = undefined;\n", .{e.oname});
            try writer.print("                        try s.read(reader, allocator);\n", .{});
            try writer.print("                        defer s.deinit(allocator);\n", .{});
            try writer.print("                        if(self.handlers.{s}_handler) |pfn| try pfn(self.user_context, &s);\n", .{e.oname});
            try writer.print("                    }},\n", .{});
        }

        try writer.print("                    else => {{std.debug.print(\"Found Packet ID {{}} in state {s}\", .{{id}});}}\n", .{struct_pair.state.name});
        try writer.print("                }}\n", .{});
        try writer.print("            }},\n", .{});
    }

    try writer.print("        }}\n", .{});

    try writer.print("    }}\n\n", .{});

    // Writer Structure

    try writer.print(dispatch_write_stub, .{});
    try writer.print("        switch(self.state) {{\n", .{});

    for (self.state_struct_array.items) |struct_pair| {
        try writer.print("            .{s} => {{\n", .{struct_pair.state.name});
        try writer.print("                switch(id) {{\n", .{});

        for (struct_pair.entries) |e| {
            const my_dir = self.ir.direction == .Out;
            const is_in = std.mem.containsAtLeast(u8, e.oname, 1, "In");
            const is_out = std.mem.containsAtLeast(u8, e.oname, 1, "Out") or std.mem.containsAtLeast(u8, e.oname, 1, "InOut");

            if ((!my_dir or !is_out) and (my_dir or !is_in)) continue;

            try writer.print("                    {} => {{\n", .{e.value});
            try writer.print("                        var s : *{s} = @ptrCast(@alignCast(ctx));\n", .{e.oname});
            try writer.print("                        try s.write(writer);\n", .{});
            try writer.print("                    }},\n", .{});
        }

        try writer.print("                    else => {{std.debug.print(\"Found Packet ID {{}} in state {s}\", .{{id}});}}\n", .{struct_pair.state.name});
        try writer.print("                }}\n", .{});
        try writer.print("            }},\n", .{});
    }

    try writer.print("        }}\n", .{});

    try writer.print("    }}\n\n", .{});

    try writer.print("}};\n", .{});
}

fn write_struct_name(self: *Self, writer: anytype, e: IR.Structure) ![]const u8 {
    try writer.print("pub const ", .{});

    if (e.flag.packet) {
        if (e.flag.compressed) {
            if (e.flag.encrypted) {
                try writer.print("CompEncPacket = struct {{\n", .{});
                return "CompEncPacket";
            } else {
                try writer.print("CompPacket = struct {{\n", .{});
                return "CompPacket";
            }
        } else if (e.flag.encrypted) {
            try writer.print("EncPacket = struct {{\n", .{});
            return "EncPacket";
        } else {
            try writer.print("Packet = struct {{\n", .{});
            return "Packet";
        }
    }

    var name: []const u8 = e.name;
    if (e.flag.event) {
        // zig fmt: off
        name =  if (e.flag.in)
                if (e.flag.out)
                    try std.fmt.allocPrint(util.allocator(), "InOut{s}", .{e.name})
                else
                    try std.fmt.allocPrint(util.allocator(), "In{s}", .{e.name})
                else
                    try std.fmt.allocPrint(util.allocator(), "Out{s}", .{e.name});
        // zig fmt: on
    }

    try writer.print("{s}", .{name});

    // If it's not a base struct, print the state
    if (!e.flag.state_base) {
        const state_num = e.state;

        for (self.ir.symbol_table.entries.items) |sym| {
            if (sym.type == .State and sym.value == state_num) {
                try writer.print("{s}", .{sym.name});
                name = try std.fmt.allocPrint(util.allocator(), "{s}{s}", .{ name, sym.name });
                break;
            }
        }
    }

    try writer.print(" = struct {{\n", .{});
    return name;
}

fn write_handle_table(ctx: *anyopaque, writer: std.io.AnyWriter) !void {
    const self = coerce(ctx);

    self.state_struct_array = std.ArrayList(StateStructPair).init(util.allocator());
    try writer.print("pub const ProtoHandlers = struct {{\n", .{});
    for (self.state_fields.items) |state| {
        var state_array = std.ArrayList(StructFields).init(util.allocator());

        for (self.ir.struct_table.entries.items) |e| {
            if (e.flag.state_base or e.state == state.value) {
                if (e.flag.event) {
                    const inout = if (e.flag.in and e.flag.out) "InOut" else if (e.flag.in) "In" else "Out";
                    const name = try std.fmt.allocPrint(util.allocator(), "{s}{s}{s}", .{ inout, e.name, state.name });
                    const new_name = try std.fmt.allocPrint(util.allocator(), "P_{s}", .{name});

                    try writer.print("   {s}_handler: ?*const fn (ctx: ?*anyopaque, event: *{s}) anyerror!void = null,\n", .{ name, name });
                    try state_array.append(.{
                        .name = new_name,
                        .oname = name,
                        .value = @bitCast(e.event),
                    });
                }
            }
        }

        try self.state_struct_array.append(StateStructPair{
            .state = state,
            .entries = try state_array.toOwnedSlice(),
        });
    }
    try writer.print("}};\n\n", .{});
}

const proto_header =
    \\pub const Protocol = struct {{
    \\    state: ProtoState = @enumFromInt(0),
    \\    compressed: bool = false,
    \\    encrypted: bool = false,
    \\    handlers: ProtoHandlers = ProtoHandlers{{}},
    \\
    \\    user_context: ?*anyopaque = null,
    \\
    \\    src_reader: std.io.AnyReader = undefined,
    \\    src_writer: std.io.AnyWriter = undefined,
    \\
    \\    const Self = @This();
    \\
    \\    pub fn init(handlers: ProtoHandlers, reader: std.io.AnyReader, writer: std.io.AnyWriter) Self {{
    \\        return .{{ 
    \\            .handlers = handlers,
    \\            .src_reader = reader,
    \\            .src_writer = writer,
    \\        }};
    \\    }}
    \\
    \\    pub fn poll(self: *Self, allocator: std.mem.Allocator) !void {{
    \\        if(self.compressed or self.encrypted) {{
    \\            @panic("Compression and encryption not supported yet");  
    \\        }}
    \\
    \\        // Read the packet len
    \\        var packet: Packet = undefined;
    \\
;
pub const len_prefix =
    \\        
    \\        packet.len = blk: {{ var value : usize = 0; var b : usize = try self.src_reader.readByte(); while(b & 0x80 != 0) {{value |= (b & 0x7F) << 7; value <<= 7; b = try self.src_reader.readByte();}} value |= b; break :blk value; }};
    \\
    \\        // Read the packet all into a buffer
    \\        const packet_len : usize = @intCast(packet.len);
    \\        const buffer = try self.src_reader.readAllAlloc(allocator, packet_len);
    \\        defer allocator.free(buffer);
    \\
    \\        var fbstream = std.io.fixedBufferStream(buffer);
    \\        const fbreader = fbstream.reader().any();
    \\
    \\        try packet.read(fbreader, allocator, self);
;

pub const id_prefix =
    \\        try packet.read(self.src_reader, allocator, self);
;
pub const dispatch_read_stub =
    \\    }}
    \\
    \\    pub fn dispatch_read(self: *Self, reader: std.io.AnyReader, allocator: std.mem.Allocator, id: usize) !void {{
    \\
;

pub const dispatch_write_stub =
    \\
    \\    pub fn dispatch_write(self: *Self, writer: std.io.AnyWriter, id: usize, ctx: *anyopaque) !void {{
    \\
;
