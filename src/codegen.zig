const std = @import("std");
const Sema = @import("sema.zig");

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
            .Union => "PacketData",
        };

        try writer.print("    {s}: {s},\n", .{ entry.name, eTypename });
    }

    try writer.print("}};\n\n", .{});
}

pub fn generate(self: *Self, writer: anytype) !void {
    try writer.print("pub const VarInt = usize;\n\n", .{});
    try writer.print("pub const PacketData = [*]u8;\n\n", .{});

    try writer.print(
        \\pub const Endian = enum {{
        \\    Little,
        \\    Big,
        \\}};
        \\
        \\pub const Direction = enum {{
        \\    In,
        \\    Out,
        \\}};
        \\
        \\
    , .{});

    try writer.print("pub const proto_endian: Endian = .{s};\n\n", .{@tagName(self.sema.endian)});
    try writer.print("pub const proto_direction: Direction = .{s};\n\n", .{@tagName(self.sema.direction)});

    // Protocol internal states enum
    try writer.print("pub const ProtoState = enum(u16) {{\n", .{});
    for (self.sema.symbol_table.entries.items) |sym| {
        if (sym.type == .State) {
            try writer.print("    {s} = {},\n", .{ sym.name, sym.value });
        }
    }
    try writer.print("}};\n\n", .{});

    for (self.sema.enum_table.entries.items) |e| {
        try self.print_enum(writer, e);
    }

    for (self.sema.struct_table.entries.items) |e| {
        try self.print_struct(writer, e);
    }
}
