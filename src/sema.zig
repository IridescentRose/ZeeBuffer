const std = @import("std");
const util = @import("util.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");

const SymType = enum(u8) {
    State = 0, // State is a reserved enumeration
    Enum = 1, // This is a global enumeration
    Literal = 2, // This is an integer literal
    UserType = 3, // This is a user-defined type
    BaseType = 4, // This is a base type
};

const BaseType = enum(u32) {
    U8 = 0,
    U16 = 1,
    U32 = 2,
    U64 = 3,
    I8 = 4,
    I16 = 5,
    I32 = 6,
    I64 = 7,
    F32 = 8,
    F64 = 9,
    Bool = 10,
    VarInt = 11,
};

const SymEntry = struct {
    name: []const u8,
    type: SymType,
    value: u32 = 0, // TODO: Make this something more generic
};

const SymTable = struct {
    entries: std.ArrayList(SymEntry),
};

const base_symbols = [_]SymEntry{
    SymEntry{ .name = "u8", .type = SymType.BaseType, .value = @intFromEnum(BaseType.U8) },
    SymEntry{ .name = "u16", .type = SymType.BaseType, .value = @intFromEnum(BaseType.U16) },
    SymEntry{ .name = "u32", .type = SymType.BaseType, .value = @intFromEnum(BaseType.U32) },
    SymEntry{ .name = "u64", .type = SymType.BaseType, .value = @intFromEnum(BaseType.U64) },
    SymEntry{ .name = "i8", .type = SymType.BaseType, .value = @intFromEnum(BaseType.I8) },
    SymEntry{ .name = "i16", .type = SymType.BaseType, .value = @intFromEnum(BaseType.I16) },
    SymEntry{ .name = "i32", .type = SymType.BaseType, .value = @intFromEnum(BaseType.I32) },
    SymEntry{ .name = "i64", .type = SymType.BaseType, .value = @intFromEnum(BaseType.I64) },
    SymEntry{ .name = "f32", .type = SymType.BaseType, .value = @intFromEnum(BaseType.F32) },
    SymEntry{ .name = "f64", .type = SymType.BaseType, .value = @intFromEnum(BaseType.F64) },
    SymEntry{ .name = "bool", .type = SymType.BaseType, .value = @intFromEnum(BaseType.Bool) },
    SymEntry{ .name = "varint", .type = SymType.BaseType, .value = @intFromEnum(BaseType.VarInt) },
};

const StructureFlag = packed struct(u8) {
    compressed: bool, // Is this compressed?
    encrypted: bool, // Is this encrypted
    in: bool, // Direction
    out: bool, // Direction
    event: bool, // Is an Event
    packet: bool, // Is a Packet
    data: bool, // Data structure
    reserved: u1, // Reserved
};

const Index = u16;

const StructureType = struct {
    user: bool = false,
    index: Index, // If user is false, this is an index into the symtable, otherwise it is an index into the struct table
};

const StructureEntry = struct {
    name: []const u8,
    type: StructureType,
};

const Structure = struct {
    name: []const u8,
    flag: StructureFlag,
    entries: []StructureEntry,
    extra: [2]Index, // Index of compression or encryption types
};

symbol_table: SymTable,
source_contents: []const u8,
token_list: []Tokenizer.Token,

const Self = @This();

fn create_default_table() !SymTable {
    var array = std.ArrayList(SymEntry).init(util.allocator());

    try array.appendSlice(base_symbols[0..]);
    return SymTable{
        .entries = array,
    };
}

pub fn create(source: []const u8, tokens: []Tokenizer.Token) !Self {
    return Self{
        .symbol_table = try create_default_table(),
        .source_contents = source,
        .token_list = tokens,
    };
}

fn token_text(self: *Self, token: Tokenizer.Token) []const u8 {
    return self.source_contents[token.start .. token.start + token.len];
}

fn token_text_idx(self: *Self, idx: Parser.Index) []const u8 {
    return self.token_text(self.token_list[idx]);
}

fn add_state_enum(self: *Self, protocol: *Parser.Protocol) !void {
    // Find the state entry
    var idx: ?usize = null;
    for (protocol.entries.items, 0..) |e, i| {
        if (e.special == .State) {
            if (idx != null) {
                @panic("State is defined twice!");
                //TODO: Better error handling
            }

            idx = i;
        }
    }

    if (idx == null) {
        @panic("State is not defined!");
    }

    const e = protocol.entries.swapRemove(idx.?);

    // Add the state symbols
    for (e.fields) |f| {
        try self.symbol_table.entries.append(.{
            .name = self.token_text_idx(f.name),
            .type = .State,
            .value = try std.fmt.parseInt(
                u32,
                self.token_text_idx(f.kind),
                0,
            ),
        });
    }
}

fn add_enums(self: *Self, protocol: *Parser.Protocol) !void {
    var free_indices = std.ArrayList(usize).init(util.allocator());
    defer free_indices.deinit();

    for (protocol.entries.items, 0..) |e, i| {
        if (e.attributes) |attribs| {
            for (attribs) |a| {
                if (a.type == .Enum) {
                    // Entry is an enum
                    try free_indices.append(i);

                    // Go through each field
                    for (e.fields) |f| {
                        try self.symbol_table.entries.append(.{
                            .name = self.token_text_idx(f.name),
                            .type = .Enum,
                            .value = try std.fmt.parseInt(
                                u32,
                                self.token_text_idx(f.kind),
                                0,
                            ),
                        });
                    }
                }
            }
        }
    }

    var duplicate = std.ArrayList(Parser.Entry).init(util.allocator());
    defer duplicate.deinit();

    for (protocol.entries.items, 0..) |e, i| {
        for (free_indices.items) |j| {
            if (i == j) {
                continue;
            }

            try duplicate.append(e);
        }
    }

    protocol.entries.clearAndFree();
    protocol.entries = std.ArrayList(Parser.Entry).fromOwnedSlice(util.allocator(), try duplicate.toOwnedSlice());
}

pub fn analyze(self: *Self, protocol: *Parser.Protocol) !void {
    std.debug.print("Analyzing Protocol...\n", .{});

    // Build enum / state symbol table to resolve
    try self.add_state_enum(protocol);
    try self.add_enums(protocol);

    // Build type symbol table

    // Resolve all fields
}
