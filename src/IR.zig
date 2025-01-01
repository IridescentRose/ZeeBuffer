const std = @import("std");

const util = @import("util.zig");

const AST = @import("AST.zig");
const SourceObject = @import("SourceObject.zig");
pub const Index = AST.Index;

const Self = @This();

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
};

pub const SymbolType = enum(u8) {
    BaseType = 0,
    UserType = 1,
    State = 2,
    Enum = 3,
};

pub const Symbol = struct {
    name: []const u8,
    type: SymbolType,
    value: u32 = 0, // If it's an Enum, this value is filled with the enum value
};

pub const StructureType = enum(u8) {
    Base = 0,
    User = 1,
    FixedArray = 2,
    VarArray = 3,
};

pub const Direction = enum(u8) {
    Client = 0,
    Server = 1,
    Both = 2,
};

pub const StructureEntry = struct {
    name: []const u8,
    type: StructureType,
    value: Index, // Index to symbol table for type
    extra: Index = 0, // If type is FixedArray, this is the size of the array; If type is VarArray, this is the index of the size field type
};

pub const Structure = struct {
    name: []const u8,
    entries: []StructureEntry,
    event: bool = false,
    event_id: ?u16 = null, // ID Number
    state_id: ?u16 = null, // Symbol Table Index for State
    direction: ?Direction = null, // Direction of the event
};

pub const EnumEntry = struct {
    name: []const u8,
    value: u32, // Is the value of the entry.
};

pub const Enum = struct {
    name: []const u8,
    backing_type: Index, // An index into the symbol table
    entries: []EnumEntry,
};

sym_tab: std.ArrayList(Symbol),
struct_tab: std.ArrayList(Structure),
enum_tab: std.ArrayList(Enum),
source: SourceObject,
endian: AST.Endian = .little,

pub fn init(source: SourceObject) !Self {
    return .{
        .sym_tab = try create_default_table(),
        .struct_tab = std.ArrayList(Structure).init(util.allocator()),
        .enum_tab = std.ArrayList(Enum).init(util.allocator()),
        .source = source,
    };
}

fn create_default_table() !std.ArrayList(Symbol) {
    var array = std.ArrayList(Symbol).init(util.allocator());
    try array.appendSlice(
        &[_]Symbol{
            Symbol{ .name = "u8", .type = .BaseType, .value = @intFromEnum(BaseType.U8) },
            Symbol{ .name = "u16", .type = .BaseType, .value = @intFromEnum(BaseType.U16) },
            Symbol{ .name = "u32", .type = .BaseType, .value = @intFromEnum(BaseType.U32) },
            Symbol{ .name = "u64", .type = .BaseType, .value = @intFromEnum(BaseType.U64) },
            Symbol{ .name = "i8", .type = .BaseType, .value = @intFromEnum(BaseType.I8) },
            Symbol{ .name = "i16", .type = .BaseType, .value = @intFromEnum(BaseType.I16) },
            Symbol{ .name = "i32", .type = .BaseType, .value = @intFromEnum(BaseType.I32) },
            Symbol{ .name = "i64", .type = .BaseType, .value = @intFromEnum(BaseType.I64) },
            Symbol{ .name = "f32", .type = .BaseType, .value = @intFromEnum(BaseType.F32) },
            Symbol{ .name = "f64", .type = .BaseType, .value = @intFromEnum(BaseType.F64) },
            Symbol{ .name = "bool", .type = .BaseType, .value = @intFromEnum(BaseType.Bool) },
        },
    );

    return array;
}

pub fn add_to_sym_tab(self: *Self, symbol: Symbol) !void {
    // Ensure the symbol doesn't already exist
    for (self.sym_tab.items) |s| {
        if (std.mem.eql(u8, s.name, symbol.name)) {
            return error.SymbolAlreadyExists;
        }
    }

    try self.sym_tab.append(symbol);
}

pub fn add_to_enum_tab(self: *Self, enumeration: Enum) !void {
    // Ensure the enum doesn't already exist
    for (self.enum_tab.items) |e| {
        if (std.mem.eql(u8, e.name, enumeration.name)) {
            return error.EnumAlreadyExists;
        }
    }

    try self.enum_tab.append(enumeration);
}

pub fn add_to_struct_tab(self: *Self, structure: Structure) !void {
    // Ensure the struct doesn't already exist
    for (self.struct_tab.items) |s| {
        if (std.mem.eql(u8, s.name, structure.name)) {
            return error.StructureAlreadyExists;
        }
    }

    try self.struct_tab.append(structure);
}
