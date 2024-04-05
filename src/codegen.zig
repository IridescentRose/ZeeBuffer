const std = @import("std");
const util = @import("util.zig");
const IR = @import("IR.zig");

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

const Self = @This();

pub fn init(ir: IR) Self {
    return Self{
        .ir = ir,
    };
}

fn print_enum(self: *Self, writer: anytype, e: IR.Enum) !void {
    const typename = self.ir.symbol_table.entries.items[e.type].name;

    try writer.print("pub const {s} = enum({s}) {{\n", .{ e.name, typename });

    for (e.entries) |entry| {
        try writer.print("    {s} = {},\n", .{ entry.name, entry.value });
    }

    try writer.print("}};\n\n", .{});
}

fn write_struct_name(self: *Self, writer: anytype, e: IR.Structure) !void {
    try writer.print("pub const ", .{});

    if (e.flag.packet) {
        if (e.flag.compressed) {
            if (e.flag.encrypted) {
                return writer.print("CompEncPacket = struct {{\n", .{});
            } else {
                return writer.print("CompPacket = struct {{\n", .{});
            }
        } else if (e.flag.encrypted) {
            return writer.print("EncPacket = struct {{\n", .{});
        } else {
            return writer.print("Packet = struct {{\n", .{});
        }
    }

    if (e.flag.data) {
        try writer.print("{s}", .{e.name});
    } else if (e.flag.event) {
        if (e.flag.in) {
            if (e.flag.out) {
                try writer.print("InOut{s}", .{e.name});
            } else {
                try writer.print("In{s}", .{e.name});
            }
        } else {
            try writer.print("Out{s}", .{e.name});
        }
    } else unreachable;

    if (!e.flag.state_base) {
        const state_num = e.state;

        for (self.ir.symbol_table.entries.items) |sym| {
            if (sym.type == .State and sym.value == state_num) {
                try writer.print("{s}", .{sym.name});
                break;
            }
        } else unreachable;
    }

    return writer.print(" = struct {{\n", .{});
}

fn print_struct(self: *Self, writer: anytype, e: IR.Structure) !void {
    try self.write_struct_name(writer, e);

    for (e.entries) |entry| {
        const eType = entry.type;

        const eTypename = switch (eType.type) {
            .Base, .User => self.ir.symbol_table.entries.items[eType.value].name,
            .Union => "EventData",
        };

        try writer.print("    {s}: {s},\n", .{ entry.name, eTypename });
    }

    try writer.print("}};\n\n", .{});
}

pub fn generate(self: *Self, writer: anytype) !void {
    try writer.print("const std = @import(\"std\");\n\n", .{});
    try writer.print("pub const VarInt = u128;\n\n", .{});
    try writer.print("pub const EventData = [*]u8;\n\n", .{});

    var state_fields = std.ArrayList(StateFields).init(util.allocator());
    defer state_fields.deinit();

    // Protocol internal states enum
    try writer.print("pub const ProtoState = enum(u16) {{\n", .{});
    for (self.ir.symbol_table.entries.items) |sym| {
        if (sym.type == .State) {
            try writer.print("    {s} = {},\n", .{ sym.name, sym.value });
            try state_fields.append(.{ .name = sym.name, .value = @intCast(sym.value) });
        }
    }
    try writer.print("}};\n\n", .{});

    for (self.ir.enum_table.entries.items) |e| {
        try self.print_enum(writer, e);
    }

    for (self.ir.struct_table.entries.items) |e| {
        try self.print_struct(writer, e);
    }

    var state_struct_array = std.ArrayList(StateStructPair).init(util.allocator());
    try writer.print("pub const ProtoHandlers = struct {{\n", .{});
    for (state_fields.items) |state| {
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

        try state_struct_array.append(StateStructPair{
            .state = state,
            .entries = try state_array.toOwnedSlice(),
        });
    }
    try writer.print("}};\n\n", .{});

    // Generate the handlers struct
    const endian_string = if (self.ir.endian == .Big) ".big" else ".little";

    // Find the field name for the packet id
    const packet_idname = for (self.ir.struct_table.entries.items) |entry| {
        const found: ?[]const u8 = for (entry.entries) |f| {
            if (f.type.type == .Union) {
                break self.ir.source.token_text_idx(f.type.value);
            }
        } else null;

        if (found != null) break found;
    } else unreachable;

    try writer.print(proto_header, .{ packet_idname.?, endian_string, endian_string, endian_string, endian_string });

    {
        // Print the dispatch function
        try writer.print(
            \\    pub fn dispatch(self: *Self, id: usize, buf_reader: std.io.AnyReader) !void {{
            \\        const state = self.state;
            \\        const handlers = self.handlers;
            \\
            \\        switch(state) {{
            \\
        , .{});

        for (state_struct_array.items) |pair| {
            // Start case
            try writer.print(
                \\            .{s} => {{
                \\
            , .{pair.state.name});

            const direction = self.ir.direction == .In;

            var count: usize = 0;
            for (pair.entries) |s| {
                const is_in = std.mem.containsAtLeast(u8, s.name, 1, "P_In");
                const is_out = std.mem.containsAtLeast(u8, s.name, 1, "P_Out") or std.mem.containsAtLeast(u8, s.name, 1, "P_InOut");

                const in_dir = (is_in and direction) or (is_out and !direction);

                if (in_dir) {
                    if (count == 0) {
                        try writer.print("                if(id == {}) {{\n", .{s.value});
                    } else {
                        try writer.print("                else if(id == {}) {{\n", .{s.value});
                    }
                    count += 1;

                    try writer.print("                    var event = try self.parse_data({s}, buf_reader);\n", .{s.oname});
                    try writer.print("                    if(handlers.{s}_handler) |hnd| {{\n", .{s.oname});
                    try writer.print("                        try hnd(self.user_context, &event);\n", .{});
                    try writer.print("                    }}\n", .{});
                    try writer.print("                    return;\n", .{});
                    try writer.print("                }}\n", .{});
                }
            }

            if (count != 0) {
                try writer.print("                else {{\n", .{});
                try writer.print("                    return error.PacketInInvalidState;\n", .{});
                try writer.print("                }}\n", .{});
            }

            // Close case
            try writer.print("            }},\n", .{});
        }

        // Close switch
        try writer.print("        }}\n", .{});

        // Close func
        try writer.print("    }}\n", .{});
    }

    try writer.print("}};\n", .{});
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
    \\        packet.len = try self.parse_data(@TypeOf(packet.len), self.src_reader);
    \\
    \\        // Read the packet all into a buffer
    \\        const packet_len : usize = @intCast(packet.len);
    \\        const buffer = try self.src_reader.readAllAlloc(allocator, packet_len);
    \\
    \\        var fbstream = std.io.fixedBufferStream(buffer);
    \\        const anyreader = fbstream.reader().any();
    \\
    \\        inline for(std.meta.fields(@TypeOf(packet))[1..]) |field| {{
    \\            switch(@typeInfo(field.type)) {{
    \\                .Pointer => |info| {{
    \\                    if(info.size == .Many) {{
    \\                        break;
    \\                    }}
    \\                }},
    \\                else => {{}}
    \\            }}
    \\            @field(packet, field.name) = try self.parse_data(field.type, anyreader);
    \\        }}
    \\
    \\        const id = @field(packet, "{s}");
    \\        try self.dispatch(@intCast(id), anyreader);
    \\    }}
    \\
    \\    fn parse_data(self: *Self, comptime T: type, buf_reader: std.io.AnyReader) !T {{
    \\        switch(@typeInfo(T)) {{
    \\            .Bool => {{
    \\                return try buf_reader.readByte() != 0;
    \\            }},
    \\            .Int => |info| {{
    \\                if(info.bits == 128) {{
    \\                    var value: u128 = 0;
    \\           
    \\                    var b = try buf_reader.readByte();
    \\                    while(b & 0x80 != 0) {{
    \\                        value |= (b & 0x7F) << 7;
    \\                        value <<= 7;
    \\                        b = try buf_reader.readByte();
    \\                    }}
    \\
    \\                    value |= b;
    \\                    return value;
    \\                }} else {{
    \\                    return try buf_reader.readInt(T, {s});
    \\                }}
    \\            }},
    \\            .Float => |info| {{
    \\                if(info.bits == 32) {{
    \\                    return @bitCast(try buf_reader.readInt(u32, {s}));
    \\                }} else if(info.bits == 64) {{
    \\                    return @bitCast(try buf_reader.readInt(u64, {s}));
    \\                }} else {{
    \\                    @compileError("Unsupported float size");
    \\                }}
    \\            }},
    \\            .Enum => |info| {{
    \\                return @enumFromInt(try buf_reader.readInt(info.tag_type, {s}));
    \\            }},
    \\            .Struct => |info| {{
    \\                var packet_data : T = undefined;
    \\                inline for(info.fields) |field| {{
    \\                    @field(packet_data, field.name) = try self.parse_data(field.type, buf_reader);
    \\                }}
    \\                return packet_data;
    \\            }},
    \\            .Pointer => |info| {{
    \\                if(info.size == .Many) {{
    \\                    // If we're here it's a packet dispatch
    \\                    return undefined;
    \\                }} else {{
    \\                    @compileError("Unsupported pointer size");
    \\                }}
    \\            }},
    \\            else => @compileError("Unsupported type for packet data"),
    \\        }}
    \\    }}
    \\
;
