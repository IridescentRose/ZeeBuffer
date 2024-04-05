const std = @import("std");
const util = @import("../util.zig");
const Tokenizer = @import("Tokenizer.zig");
const Parser = @import("Parser.zig");
const AST = @import("../AST.zig");
const IR = @import("../IR.zig");
const SourceObject = @import("../SourceObject.zig");

const Self = @This();

source: SourceObject,

pub fn init(source: SourceObject) Self {
    return Self{
        .source = source,
    };
}

const AttributeDetails = struct {
    flag: IR.StructureFlag,
    state: i16,
    event: i16,
};

fn generate_attrib_details(self: *Self, e: AST.Entry, ir: *IR) !?AttributeDetails {
    // Initialize values
    var flag = IR.StructureFlag{
        .data = true,
        .state_base = true,
        .encrypted = false,
        .compressed = false,
        .in = false,
        .out = false,
        .event = false,
        .packet = false,
    };

    var state: i16 = -1;
    var event: i16 = -1;

    if (e.attributes) |attribs| {
        for (attribs) |a| {
            switch (a.type) {
                .Compressed => flag.compressed = true, // TODO: Parse type
                .Encrypted => flag.encrypted = true, // TODO: Parse type
                .InEvent => {
                    flag.in = true;
                    flag.event = true;
                    event = try std.fmt.parseInt(i16, self.source.token_text_idx(a.value), 0);
                },
                .OutEvent => {
                    flag.out = true;
                    flag.event = true;
                    event = try std.fmt.parseInt(i16, self.source.token_text_idx(a.value), 0);
                },
                .InOutEvent => {
                    flag.in = true;
                    flag.out = true;
                    flag.event = true;
                    event = try std.fmt.parseInt(i16, self.source.token_text_idx(a.value), 0);
                },
                .State => {
                    flag.state_base = false;
                    const value = self.source.token_text_idx(a.value);
                    state = std.fmt.parseInt(i16, value, 0) catch blk: {
                        // So we probably have a user-defined state, let's look it up
                        const sym = ir.resolve_symbol(value) catch {
                            std.debug.print("Cannot find state enumeration: {s}\n", .{value});

                            const token = self.source.tokens[a.value];
                            const source = self.source.get_source_string(token);
                            const location = self.source.get_source_location(token);

                            std.debug.print("In Struct {s}\n", .{self.source.token_text_idx(e.name)});
                            std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                            std.debug.print("{s}\n", .{source});

                            return error.SemanticStateNotFound;
                        };

                        break :blk @intCast(sym.value);
                    };
                },
                .Enum => {
                    return null;
                },
            }
        }
    }

    flag.packet = e.special == .Packet;
    flag.data = !flag.event;

    return .{
        .flag = flag,
        .state = state,
        .event = event,
    };
}

fn add_state_symbols(self: *Self, ast: AST, ir: *IR) !void {
    // Find the state entry
    var idx: ?usize = null;

    for (ast.entries, 0..) |e, i| {
        if (e.special == .State) {
            // Check if the state is defined more than once
            if (idx != null) {
                std.debug.print("State is defined more than once!\nOnly one @state entry is permitted!\n", .{});
                return error.SemanticStateRedefinition;
            }

            idx = i;
        }
    }

    // Check if state wasn't defined
    if (idx == null) {
        std.debug.print("State is not defined!\n Use @state to define the protocol state enum.\n", .{});
        return error.SemanticStateNotDefined;
    }

    const e = ast.entries[idx.?];

    // Add the state symbols
    for (e.fields) |f| {
        try ir.symbol_table.entries.append(.{
            .name = self.source.token_text_idx(f.name),
            .type = .State,
            .value = try std.fmt.parseInt(
                u32,
                self.source.token_text_idx(f.kind),
                0,
            ),
        });
    }
}

fn add_enum_entries(self: *Self, ast: AST, ir: *IR) !void {
    // Go through entries
    for (ast.entries) |e| {
        if (e.attributes == null) continue;

        // Go through attributes
        for (e.attributes.?) |a| {
            if (a.type != .Enum) continue;

            // Enum entries
            var entries = std.ArrayList(IR.EnumEntry).init(util.allocator());

            // Enum backing type check
            const valStr = self.source.token_text_idx(a.value);
            const eType = for (ir.symbol_table.entries.items, 0..) |sym, i| {
                if (sym.type == .BaseType and std.mem.eql(u8, valStr, sym.name)) {
                    break i;
                }
            } else {
                std.debug.print("Cannot find enum backing type: {s}!\n", .{valStr});

                const token = self.source.tokens[e.name];
                const source = self.source.get_source_string(token);
                const location = self.source.get_source_location(token);

                std.debug.print("In Enum {s}\n", .{ir.source.token_text(token)});
                std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                std.debug.print("{s}\n", .{source});

                return error.SemanticEnumBackingTypeNotFound;
            };

            // Add each enum field
            for (e.fields) |f| {
                try entries.append(.{
                    .name = self.source.token_text_idx(f.name),
                    .value = try std.fmt.parseInt(
                        u32,
                        self.source.token_text_idx(f.kind),
                        0,
                    ),
                });
            }

            // Add enum to the IR
            try ir.enum_table.entries.append(.{
                .name = self.source.token_text_idx(e.name),
                .type = @intCast(eType),
                .entries = try entries.toOwnedSlice(),
            });
        }
    }
}

fn add_struct_data_symbols(self: *Self, ast: AST, ir: *IR) !void {
    for (ast.entries) |e| {
        // Check if enum, if not, skip
        // zig fmt: off
        if (e.attributes != null
            and for (e.attributes.?) |a| {
                    if (a.type == .Enum) break false;
                } else true
            ) continue;
        // zig fmt: on

        try ir.symbol_table.entries.append(.{
            .name = self.source.token_text_idx(e.name),
            .type = .UserType,
        });
    }
}

fn add_struct_entries(self: *Self, ast: AST, ir: *IR) !void {
    for (ast.entries) |e| {
        if (e.special == .State) continue;

        // Grab attribute details
        var attrib_details: AttributeDetails = undefined;
        if (try self.generate_attrib_details(e, ir)) |details| {
            attrib_details = details;
        } else {
            continue;
        }

        // Create entries
        var entries = std.ArrayList(IR.StructureEntry).init(util.allocator());

        for (e.fields) |f| {
            var kind: IR.StructureTypes = .Base;
            var entry: IR.SymEntry = undefined;
            var index: usize = 0;
            var extra: usize = 0;

            if (f.len_kind == 3) {
                const name = self.source.token_text_idx(f.kind);
                if (std.mem.eql(u8, name, "Event")) {
                    kind = .Union;
                    index = f.kind + 2;
                } else {
                    const token = self.source.tokens[f.kind];
                    const source = self.source.get_source_string(token);
                    const location = self.source.get_source_location(token);

                    std.debug.print("In Struct {s}\n", .{self.source.token_text_idx(e.name)});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});

                    return error.SemanticMacroNotFound;
                }
            } else if (f.len_kind == 4) {
                const name = self.source.token_text_idx(f.kind);
                if (std.mem.eql(u8, name, "VarArray")) {
                    kind = .VarArray;
                    index = f.kind + 2;
                    extra = f.kind + 3;
                    //TODO: Check the subtypes

                } else if (std.mem.eql(u8, name, "Array")) {
                    kind = .FixedArray;
                    index = f.kind + 2;
                    extra = f.kind + 3;

                    //TODO: Check the subtypes
                } else {
                    const token = self.source.tokens[f.kind];
                    const source = self.source.get_source_string(token);
                    const location = self.source.get_source_location(token);

                    std.debug.print("In Struct {s}\n", .{self.source.token_text_idx(e.name)});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});

                    return error.SemanticMacroNotFound;
                }
            } else {
                if (ir.resolve_symbol(self.source.token_text_idx(f.kind))) |k| {
                    entry = k;
                    switch (k.type) {
                        .BaseType => {
                            kind = .Base;
                        },
                        .UserType => {
                            kind = .User;
                        },
                        else => unreachable,
                    }
                } else |_| {
                    std.debug.print("Cannot find type: {s}!\n", .{self.source.token_text_idx(f.kind)});

                    const token = self.source.tokens[f.kind];
                    const source = self.source.get_source_string(token);
                    const location = self.source.get_source_location(token);

                    std.debug.print("In Struct {s}\n", .{self.source.token_text_idx(e.name)});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});

                    return error.SemanticTypeNotFound;
                }

                index = for (ir.symbol_table.entries.items, 0..) |ent, i| {
                    if (std.meta.eql(ent, entry)) {
                        break i;
                    }
                } else {
                    @panic("Compiler error: Symbol not found in symbol table!\nPlease report this bug here: https://github.com/IridescentRose/ZeeBuffer/issues\n");
                };
            }

            try entries.append(IR.StructureEntry{
                .name = self.source.token_text_idx(f.name),
                .type = .{
                    .type = kind,
                    .value = @intCast(index),
                    .extra = @intCast(extra),
                },
            });
        }

        // Add struct to IR
        try ir.struct_table.entries.append(.{
            .name = self.source.token_text_idx(e.name),
            .flag = attrib_details.flag,
            .entries = try entries.toOwnedSlice(),
            .state = attrib_details.state,
            .event = attrib_details.event,
        });
    }
}

pub fn analyze(self: *Self, ast: AST) !IR {
    var ir = try IR.init(self.source);

    ir.endian = ast.endian;
    ir.direction = ast.direction;

    // Build enum / state symbol table to resolve
    try self.add_state_symbols(ast, &ir);
    try self.add_struct_data_symbols(ast, &ir);

    // Run through the protocol and add each struct to the struct table
    try self.add_enum_entries(ast, &ir);
    try self.add_struct_entries(ast, &ir);

    return ir;
}
