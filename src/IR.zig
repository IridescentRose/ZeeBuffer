const std = @import("std");
const util = @import("util.zig");
const AST = @import("AST.zig");
const SourceObject = @import("SourceObject.zig");

pub const SymType = enum(u8) {
    State = 0, // State is a reserved enumeration
    UserType = 1, // This is a user-defined type
    BaseType = 2, // This is a base type
};

// Base types
pub const BaseType = enum(u32) {
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

pub const SymEntry = struct {
    name: []const u8,
    type: SymType,
    value: u32 = 0, // TODO: Make this something more generic
};

pub const SymTable = struct {
    entries: std.ArrayList(SymEntry),
};

pub const StructureFlag = packed struct(u8) {
    compressed: bool, // Is this compressed?
    encrypted: bool, // Is this encrypted
    in: bool, // Direction
    out: bool, // Direction
    event: bool, // Is an Event
    packet: bool, // Is a Packet
    data: bool, // Data structure
    state_base: bool, // State base
};
pub const Index = u16;

pub const StructureTypes = enum(u8) {
    Base = 0,
    User = 1,
    Union = 2,
};

pub const StructureType = struct {
    type: StructureTypes = .Base,
    value: Index, // If user is false, this is an index into the symtable, otherwise it is an index into the struct table
};

pub const StructureEntry = struct {
    name: []const u8,
    type: StructureType,
};

pub const Structure = struct {
    name: []const u8,
    flag: StructureFlag,
    entries: []StructureEntry,
    state: i16 = -1,
    event: i16 = -1,
};

pub const StructureTable = struct {
    entries: std.ArrayList(Structure),
};

pub const EnumTable = struct {
    entries: std.ArrayList(Enum),
};

pub const EnumEntry = struct {
    name: []const u8,
    value: u32,
};

pub const Enum = struct {
    name: []const u8,
    type: Index,
    entries: []EnumEntry,
};

const Self = @This();

symbol_table: SymTable,
struct_table: StructureTable,
enum_table: EnumTable,
endian: AST.Endian = .Little,
direction: AST.Direction = .In,
source: SourceObject,

fn create_default_table() !SymTable {
    var array = std.ArrayList(SymEntry).init(util.allocator());

    try array.appendSlice(base_symbols[0..]);
    return SymTable{
        .entries = array,
    };
}

pub fn init(source: SourceObject) !Self {
    return .{
        .symbol_table = try create_default_table(),
        .struct_table = .{
            .entries = std.ArrayList(Structure).init(util.allocator()),
        },
        .enum_table = .{
            .entries = std.ArrayList(Enum).init(util.allocator()),
        },
        .source = source,
    };
}

pub fn resolve_symbol(self: *Self, name: []const u8) !SymEntry {
    for (self.symbol_table.entries.items) |e| {
        if (std.mem.eql(u8, e.name, name)) {
            return e;
        }
    }

    return error.SymEntryNotFound;
}

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
    SymEntry{ .name = "VarInt", .type = SymType.BaseType, .value = @intFromEnum(BaseType.VarInt) },
};
