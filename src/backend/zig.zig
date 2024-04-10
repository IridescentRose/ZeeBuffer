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

fn write_struct(ctx: *anyopaque, writer: std.io.AnyWriter, e: IR.Structure) !void {
    const self = coerce(ctx);
    const struct_name = try self.write_struct_name(writer, e);

    for (e.entries) |entry| {
        const eType = entry.type;

        const eTypename = switch (eType.type) {
            .Base,
            => blk: {
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

    const endian_string = if (self.ir.endian == .Big) ".big" else ".little";

    // Read
    try writer.print("\n    pub fn read(self: *{s}, reader: std.io.AnyReader) !{s} {{\n", .{ struct_name, struct_name });

    for (e.entries) |entry| {
        switch (entry.type.type) {
            .Base => {
                const base = self.ir.symbol_table.entries.items[entry.type.value].name;

                if (std.mem.eql(u8, base, "f32")) {
                    try writer.print("        self.{s} = @bitCast(try reader.readInt(u32, {s}));\n", .{ entry.name, endian_string });
                } else if (std.mem.eql(u8, base, "f64")) {
                    try writer.print("        self.{s} = @bitCast(try reader.readInt(u64, {s}));\n", .{ entry.name, endian_string });
                } else if (std.mem.eql(u8, base, "VarInt")) {
                    try writer.print("        self.{s} = blk: {{ var value : usize = 0; var b : usize = try reader.readByte(); while(b & 0x80 != 0) {{value |= (b & 0x7F) << 7; value <<= 7; b = try reader.readByte();}} value |= b; break :blk value; }};\n", .{entry.name});
                } else {
                    try writer.print("        self.{s} = try reader.readInt({s}, {s});\n", .{ entry.name, base, endian_string });
                }
            },
            .User => {
                try writer.print("        self.{s}.read(reader);\n", .{entry.name});
            },
            else => {
                try writer.print("        //TODO: UNFINISHED {s}!\n", .{entry.name});
            },
        }
    }
    try writer.print("    }}\n", .{});

    try writer.print("}};\n\n", .{});
}

fn write_enum(ctx: *anyopaque, writer: std.io.AnyWriter, e: IR.Enum) !void {
    const self = coerce(ctx);

    const typename = self.ir.symbol_table.entries.items[e.type].name;

    try writer.print("pub const {s} = enum({s}) {{\n", .{ e.name, typename });

    for (e.entries) |entry| {
        try writer.print("    {s} = {},\n", .{ entry.name, entry.value });
    }

    try writer.print("}};\n\n", .{});
}

fn write_footer(ctx: *anyopaque, writer: std.io.AnyWriter) !void {
    _ = coerce(ctx);

    try writer.print(proto_header, .{});
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

    std.debug.print("{s}\n", .{e.name});

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
    } else if (!e.flag.data) unreachable;

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
        } else unreachable;
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
    \\        packet.len = try self.parse_data(@TypeOf(packet.len), self.src_reader);
    \\
    \\        // Read the packet all into a buffer
    \\        const packet_len : usize = @intCast(packet.len);
    \\        const buffer = try self.src_reader.readAllAlloc(allocator, packet_len);
    \\
    \\        var fbstream = std.io.fixedBufferStream(buffer);
    \\        const anyreader = fbstream.reader().any();
    \\    }}
    \\
;
