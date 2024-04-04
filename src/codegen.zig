const std = @import("std");
const util = @import("util.zig");
const Sema = @import("sema.zig");

const StateFields = struct {
    name: []const u8,
    value: u16,
};

const StructFields = StateFields;

sema: Sema,

const Self = @This();

pub fn create(sema: Sema) !Self {
    return Self{ .sema = sema };
}

fn print_enum(self: *Self, writer: anytype, e: Sema.Enum) !void {
    const typename = self.sema.symbol_table.entries.items[e.type].name;

    try writer.print("pub const {s} = enum({s}) {{\n", .{ e.name, typename });

    for (e.entries) |entry| {
        try writer.print("    {s} = {},\n", .{ entry.name, entry.value });
    }

    try writer.print("}};\n\n", .{});
}

fn write_struct_name(self: *Self, writer: anytype, e: Sema.Structure) !void {
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
    } else {
        @panic("Invalid structure type");
    }

    if (!e.flag.state_base) {
        const state_num = e.state;

        for (self.sema.symbol_table.entries.items) |sym| {
            if (sym.type == .State and sym.value == state_num) {
                try writer.print("{s}", .{sym.name});
                break;
            }
        } else @panic("Invalid state number!");
    }

    return writer.print(" = struct {{\n", .{});
}

fn print_struct(self: *Self, writer: anytype, e: Sema.Structure) !void {
    try self.write_struct_name(writer, e);

    for (e.entries) |entry| {
        const eType = entry.type;

        const eTypename = switch (eType.user) {
            .Base, .User => self.sema.symbol_table.entries.items[eType.index].name,
            .Union => "EventData",
        };

        try writer.print("    {s}: {s},\n", .{ entry.name, eTypename });
    }

    try writer.print("}};\n\n", .{});
}

pub fn generate(self: *Self, writer: anytype) !void {
    std.debug.print("\rGenerating code...", .{});

    try writer.print("const std = @import(\"std\");\n\n", .{});
    try writer.print("pub const VarInt = u128;\n\n", .{});
    try writer.print("pub const EventData = [*]u8;\n\n", .{});

    // try writer.print(
    //     \\pub const Endian = enum {{
    //     \\    Little,
    //     \\    Big,
    //     \\}};
    //     \\
    //     \\pub const Direction = enum {{
    //     \\    In,
    //     \\    Out,
    //     \\}};
    //     \\
    //     \\
    // , .{});

    // try writer.print("pub const proto_endian: Endian = .{s};\n\n", .{@tagName(self.sema.endian)});
    // try writer.print("pub const proto_direction: Direction = .{s};\n\n", .{@tagName(self.sema.direction)});

    var state_fields = std.ArrayList(StateFields).init(util.allocator());
    defer state_fields.deinit();

    // Protocol internal states enum
    try writer.print("pub const ProtoState = enum(u16) {{\n", .{});
    for (self.sema.symbol_table.entries.items) |sym| {
        if (sym.type == .State) {
            try writer.print("    {s} = {},\n", .{ sym.name, sym.value });
            try state_fields.append(.{ .name = sym.name, .value = @intCast(sym.value) });
        }
    }
    try writer.print("}};\n\n", .{});

    for (self.sema.enum_table.entries.items) |e| {
        try self.print_enum(writer, e);
    }

    for (self.sema.struct_table.entries.items) |e| {
        try self.print_struct(writer, e);
    }

    var state_array_structs = std.ArrayList(std.ArrayList(StructFields)).init(util.allocator());
    try writer.print("pub const ProtoHandlers = struct {{\n", .{});
    for (state_fields.items) |state| {
        var state_array = std.ArrayList(StructFields).init(util.allocator());

        for (self.sema.struct_table.entries.items) |e| {
            if (e.flag.state_base or e.state == state.value) {
                if (e.flag.event) {
                    const inout = if (e.flag.in and e.flag.out) "InOut" else if (e.flag.in) "In" else "Out";
                    const name = try std.fmt.allocPrint(util.allocator(), "{s}{s}{s}", .{ inout, e.name, state.name });
                    const new_name = try std.fmt.allocPrint(util.allocator(), "P_{s}", .{name});

                    try writer.print("   {s}_handler: ?*const fn (event: *{s}) anyerror!void = null,\n", .{ name, name });
                    try state_array.append(.{
                        .name = new_name,
                        .value = @bitCast(e.event),
                    });
                }
            }
        }

        try state_array_structs.append(state_array);
    }
    try writer.print("}};\n\n", .{});

    // Now make the enums per each state that reference the indices above
    for (state_array_structs.items, 0..) |state_array, i| {
        try writer.print("pub const ProtoPacket{s}In = enum(u16) {{\n", .{state_fields.items[i].name});

        for (state_array.items) |f| {
            if (std.mem.containsAtLeast(u8, f.name, 1, "P_In")) {
                try writer.print("    {s} = {d},\n", .{ f.name, f.value });
            }
        }

        try writer.print("}};\n\n", .{});

        try writer.print("pub const ProtoPacket{s}Out = enum(u16) {{\n", .{state_fields.items[i].name});

        for (state_array.items) |f| {
            if (std.mem.containsAtLeast(u8, f.name, 1, "P_Out") or std.mem.containsAtLeast(u8, f.name, 1, "P_InOut")) {
                try writer.print("    {s} = {d},\n", .{ f.name, f.value });
            }
        }

        try writer.print("}};\n\n", .{});
    }

    // Generate the handlers struct

    // Generate the handlers struct
    const endian_string = if (self.sema.endian == .Big) ".big" else ".little";
    try writer.print(
        \\pub const Protocol = struct {{
        \\    state: ProtoState = @enumFromInt(0),
        \\    compressed: bool = false,
        \\    encrypted: bool = false,
        \\    handlers: ProtoHandlers = ProtoHandlers{{}},
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
        \\        if(std.mem.eql(u8, @typeName(@TypeOf(packet.len)), "VarInt")) {{
        \\            packet.len = 0;
        \\            
        \\            var b = try self.src_reader.readByte();
        \\            while(b & 0x80 != 0) {{
        \\                packet.len |= (b & 0x7F) << 7;
        \\                packet.len <<= 7;
        \\
        \\                b = try self.src_reader.readByte();
        \\            }}
        \\
        \\            packet.len |= b;
        \\        }} else {{
        \\           packet.len = try self.src_reader.readInt(@TypeOf(packet.len), {s});
        \\        }}
        \\
        \\        // Read the packet all into a buffer
        \\        const packet_len : usize = @intCast(packet.len);
        \\        const buffer = try self.src_reader.readAllAlloc(allocator, packet_len);
        \\
        \\        var fbstream = std.io.fixedBufferStream(buffer);
        \\        const anyreader = fbstream.reader().any();
        \\
        \\        // Parse the packet
        \\        packet.data = try self.parse_data(@TypeOf(packet.data), anyreader);
        \\    }}
        \\
        \\    fn parse_data(self: *Self, comptime T: type, buf_reader: std.io.AnyReader) !T {{
        \\        @compileLog("Parsing data of type: {{}}", @typeName(T));
        \\
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
        \\                    @compileLog("Parsing pointer of type: {{}}", @typeName(T));
        \\                }} else {{
        \\                    @compileError("Unsupported pointer size");
        \\                }}
        \\            }},
        \\            else => @compileError("Unsupported type for packet data"),
        \\        }}
        \\    }}
        \\
    , .{ endian_string, endian_string, endian_string, endian_string, endian_string });
    try writer.print("}};\n", .{});
}
