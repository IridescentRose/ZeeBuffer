const std = @import("std");
const util = @import("util.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");

const SymType = enum(u8) {
    State = 0, // State is a reserved enumeration
    UserType = 1, // This is a user-defined type
    BaseType = 2, // This is a base type
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
    SymEntry{ .name = "varInt", .type = SymType.BaseType, .value = @intFromEnum(BaseType.VarInt) },
};

const StructureTable = struct {
    entries: std.ArrayList(Structure),
};

const StructureFlag = packed struct(u8) {
    compressed: bool, // Is this compressed?
    encrypted: bool, // Is this encrypted
    in: bool, // Direction
    out: bool, // Direction
    event: bool, // Is an Event
    packet: bool, // Is a Packet
    data: bool, // Data structure
    state_base: bool, // State base
};

const Index = u16;

const StructureTypes = enum(u8) {
    Base = 0,
    User = 1,
    Union = 2,
};

const StructureType = struct {
    user: StructureTypes = .Base,
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
    state: i16 = -1,
};

const EnumTable = struct {
    entries: std.ArrayList(Enum),
};

const EnumEntry = struct {
    name: []const u8,
    value: u32,
};

const Enum = struct {
    name: []const u8,
    entries: []EnumEntry,
};

symbol_table: SymTable,
struct_table: StructureTable,
enum_table: EnumTable,
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
        .struct_table = .{
            .entries = std.ArrayList(Structure).init(util.allocator()),
        },
        .enum_table = .{
            .entries = std.ArrayList(Enum).init(util.allocator()),
        },
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

fn add_state_symbols(self: *Self, protocol: *Parser.Protocol) !void {
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

fn resolve_symbol(self: *Self, name: []const u8) !SymEntry {
    for (self.symbol_table.entries.items) |e| {
        if (std.mem.eql(u8, e.name, name)) {
            return e;
        }
    }

    return error.SymEntryNotFound;
}

fn add_enum_entries(self: *Self, protocol: *Parser.Protocol) !void {
    for (protocol.entries.items) |e| {
        if (e.attributes) |attribs| {
            for (attribs) |a| {
                if (a.type == .Enum) {
                    var entries = std.ArrayList(EnumEntry).init(util.allocator());

                    for (e.fields) |f| {
                        try entries.append(.{
                            .name = self.token_text_idx(f.name),
                            .value = try std.fmt.parseInt(
                                u32,
                                self.token_text_idx(f.kind),
                                0,
                            ),
                        });
                    }

                    try self.enum_table.entries.append(.{
                        .name = self.token_text_idx(e.name),
                        .entries = try entries.toOwnedSlice(),
                    });
                }
            }
        }
    }
}

fn add_struct_data_symbols(self: *Self, protocol: *Parser.Protocol) !void {
    for (protocol.entries.items) |e| {
        // Data
        if (e.attributes) |attribs| {
            var is_enum = false;
            for (attribs) |a| {
                if (a.type == .Enum) {
                    is_enum = true;
                    break;
                }
            }

            if (!is_enum) {
                continue;
            }
        }

        try self.symbol_table.entries.append(.{
            .name = self.token_text_idx(e.name),
            .type = .UserType,
        });
    }
}

fn add_struct_entries(self: *Self, protocol: *Parser.Protocol) !void {
    for (protocol.entries.items) |e| {
        var flag = StructureFlag{ .data = true, .state_base = true, .encrypted = false, .compressed = false, .in = false, .out = false, .event = false, .packet = false };
        var state: i16 = -1;

        var was_enum: bool = false;
        if (e.attributes) |attribs| {
            for (attribs) |a| {
                switch (a.type) {
                    .Compressed => flag.compressed = true, // TODO: Parse type
                    .Encrypted => flag.encrypted = true, // TODO: Parse type
                    .InEvent => {
                        flag.in = true;
                        flag.event = true;
                    },
                    .OutEvent => {
                        flag.out = true;
                        flag.event = true;
                    },
                    .InOutEvent => {
                        flag.in = true;
                        flag.out = true;
                        flag.event = true;
                    },
                    .State => {
                        flag.state_base = false;
                        const value = self.token_text_idx(a.value);
                        state = std.fmt.parseInt(i16, value, 0) catch blk: {
                            // So we probably have a user-defined state, let's look it up
                            const sym = try self.resolve_symbol(value);

                            if (sym.type != .State) {
                                @panic("Invalid state type"); // TODO: Better error handling
                            } else {
                                break :blk @intCast(sym.value);
                            }
                        };
                    },
                    .Enum => {
                        was_enum = true;
                        break;
                    },
                }
            }
        }

        if (was_enum) {
            continue;
        }

        if (e.special == .Packet) {
            flag.packet = true;
        }

        if (flag.event) {
            flag.data = false;
        }

        var entries = std.ArrayList(StructureEntry).init(util.allocator());

        for (e.fields) |f| {
            var user: StructureTypes = .Base;
            var entry: SymEntry = undefined;
            var index: usize = 0;

            if (f.len_kind != 0) {
                const name = self.token_text_idx(f.kind);
                if (std.mem.eql(u8, name, "Event")) {
                    user = .Union;
                    index = f.kind + 2;
                }
            } else {
                if (self.resolve_symbol(self.token_text_idx(f.kind))) |kind| {
                    entry = kind;
                    switch (kind.type) {
                        .BaseType => {
                            user = .Base;
                        },
                        .UserType => {
                            user = .User;
                        },
                        else => @panic("Invalid type"),
                    }
                } else |_| {
                    std.debug.print("Cannot find type: {s}\n", .{self.token_text_idx(f.kind)});
                    @panic("Cannot find type");
                }

                index = for (self.symbol_table.entries.items, 0..) |ent, i| {
                    if (std.meta.eql(ent, entry)) {
                        break i;
                    }
                } else {
                    @panic("Cannot find type");
                };
            }

            try entries.append(StructureEntry{
                .name = self.token_text_idx(f.name),
                .type = .{
                    .user = user,
                    .index = @intCast(index),
                },
            });
        }

        try self.struct_table.entries.append(.{
            .name = self.token_text_idx(e.name),
            .flag = flag,
            .entries = try entries.toOwnedSlice(),
            .state = state,
        });
    }
}

pub fn analyze(self: *Self, protocol: *Parser.Protocol) !void {
    std.debug.print("\rAnalyzing protocol...", .{});
    // Build enum / state symbol table to resolve
    try self.add_state_symbols(protocol);
    try self.add_struct_data_symbols(protocol);

    // Run through the protocol and add each struct to the struct table
    try self.add_enum_entries(protocol);
    try self.add_struct_entries(protocol);

    // If we've gotten here, we've successfully analyzed the protocol
}
