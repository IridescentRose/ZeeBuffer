const std = @import("std");
const assert = std.debug.assert;

const util = @import("../util.zig");

const AST = @import("../AST.zig");
const IR = @import("../IR.zig");
const SourceObject = @import("../SourceObject.zig");
const Tokenizer = @import("tokenizer.zig");

const Self = @This();

ast: AST,
source: SourceObject,

pub fn init(ast: AST, source: SourceObject) Self {
    return .{
        .ast = ast,
        .source = source,
    };
}

fn print_error(self: *Self, token: Tokenizer.Token, message: []const u8) void {
    std.debug.print("{s}\n", .{message});

    const location = self.source.get_source_location(token);
    const source = self.source.get_source_string(token);

    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
    std.debug.print("{s}\n", .{source});
}

fn add_state_symbols(self: *Self, ir: *IR) !void {
    var idx: ?usize = null;

    for (self.ast.entries, 0..) |e, i| {
        if (e.is_state) {
            if (idx != null) {
                std.debug.print("State is defined more than once!\nOnly one @state entry is permitted!\n", .{});
                return error.SemanticStateRedefinition;
            }

            idx = i;
        }
    }

    if (idx == null) {
        std.debug.print("State is not defined!\n Use @state to define the protocol state enum.\n", .{});
        return error.SemanticStateNotDefined;
    }

    const e = self.ast.entries[idx.?];
    for (e.fields) |f| {
        try ir.add_to_sym_tab(.{
            .name = self.source.get_token_text_by_idx(f.name),
            .type = .State,
            .value = try std.fmt.parseInt(
                u32,
                self.source.get_token_text_by_idx(f.values[0]),
                0,
            ),
        });
    }
}

fn add_enums(self: *Self, ir: *IR) !void {
    for (self.ast.entries) |e| {
        if (e.attribute) |attr| {
            if (attr.kind != .Enum)
                continue;

            if (attr.values.len != 1) {
                self.print_error(self.source.tokens[e.name], "Enum attribute must have exactly one value!");
                return error.SemanticEnumAttributeLength;
            }

            var entries = std.ArrayList(IR.EnumEntry).init(util.allocator());

            for (e.fields) |f| {
                const value = try std.fmt.parseInt(
                    u32,
                    self.source.get_token_text_by_idx(f.values[0]),
                    0,
                );

                try entries.append(.{
                    .name = self.source.get_token_text_by_idx(f.name),
                    .value = value,
                });

                ir.add_to_sym_tab(.{
                    .name = self.source.get_token_text_by_idx(f.name),
                    .type = .Enum,
                    .value = value,
                }) catch {
                    self.print_error(self.source.tokens[f.name], "Enum entry already exists!");
                    return error.SemanticEnumEntryAlreadyExists;
                };
            }

            const backing_type_str = self.source.get_token_text_by_idx(attr.values[0]);
            const backing_type_idx = for (ir.sym_tab.items, 0..) |s, i| {
                if (std.mem.eql(u8, s.name, backing_type_str)) {
                    break i;
                }
            } else {
                self.print_error(self.source.tokens[attr.values[0]], "Backing type not found!");
                return error.SemanticEnumBackingTypeNotFound;
            };

            ir.add_to_enum_tab(.{
                .name = self.source.get_token_text_by_idx(e.name),
                .backing_type = @intCast(backing_type_idx),
                .entries = try entries.toOwnedSlice(),
            }) catch {
                self.print_error(self.source.tokens[e.name], "Enum already exists!");
                return error.SemanticEnumAlreadyExists;
            };
        }
    }
}

fn add_struct_symbols(self: *Self, ir: *IR) !void {
    for (self.ast.entries) |e| {
        if (e.attribute != null and e.attribute.?.kind == .Enum)
            continue;

        if (e.is_state)
            continue;

        ir.add_to_sym_tab(.{
            .name = self.source.get_token_text_by_idx(e.name),
            .type = .UserType,
            .value = 0,
        }) catch {
            self.print_error(self.source.tokens[e.name], "Struct already exists!");
            return error.SemanticStructAlreadyExists;
        };
    }
}

fn add_structs(self: *Self, ir: *IR) !void {
    for (self.ast.entries) |e| {
        if (e.attribute != null and e.attribute.?.kind == .Enum)
            continue;

        if (e.is_state)
            continue;

        const event = e.attribute != null and e.attribute.?.kind == .Event;

        var event_id: ?u16 = null;
        var state_id: ?u16 = null;
        var direction: ?IR.Direction = null;

        if (event) {
            // We need to read the attribute values, which must exist at this point
            const attrib = e.attribute.?;

            if (attrib.values.len != 3) {
                std.debug.print("Event attribute must have exactly three values!\n", .{});
                return error.SemanticEventAttributeLength;
            }

            // Get the event ID
            // This could be an Enum or a number
            const event_str = self.source.get_token_text_by_idx(attrib.values[0]);
            if (std.ascii.isDigit(event_str[0])) {
                event_id = try std.fmt.parseInt(
                    u16,
                    event_str,
                    0,
                );
            } else {
                event_id = for (ir.sym_tab.items) |s| {
                    if (std.mem.eql(u8, s.name, event_str)) {
                        break @intCast(s.value);
                    }
                } else {
                    const event_tok = self.source.tokens[attrib.values[0]];
                    std.debug.print("Event not found: {s}!\n", .{event_str});
                    self.print_error(event_tok, "Event does not exist!");
                    return error.SemanticEventNotFound;
                };
            }

            // Get the state symtab ID
            const state_str = self.source.get_token_text_by_idx(attrib.values[1]);
            state_id = for (ir.sym_tab.items, 0..) |s, i| {
                if (std.mem.eql(u8, s.name, state_str)) {
                    break @intCast(i);
                }
            } else {
                const state_tok = self.source.tokens[attrib.values[1]];
                std.debug.print("State not found: {s}!\n", .{state_str});
                self.print_error(state_tok, "State does not exist!");
                return error.SemanticStateNotFound;
            };

            // Get the direction
            const dir_str = self.source.get_token_text_by_idx(attrib.values[2]);
            direction = if (std.mem.eql(u8, dir_str, "Client"))
                .Client
            else if (std.mem.eql(u8, dir_str, "Server"))
                .Server
            else if (std.mem.eql(u8, dir_str, "Both"))
                .Both
            else {
                std.debug.print("Invalid direction!\n", .{});
                return error.SemanticInvalidDirection;
            };
        }

        var entries = std.ArrayList(IR.StructureEntry).init(util.allocator());

        for (e.fields) |f| {
            var f_type: IR.StructureType = .Base;

            const f_type_str = self.source.get_token_text_by_idx(f.values[0]);

            var type_index: IR.Index = 0xFFFF;
            var extra_index: IR.Index = 0xFFFF;

            // Easy checks
            if (std.mem.eql(u8, "Array", f_type_str)) {
                f_type = .FixedArray;
            } else if (std.mem.eql(u8, "VarArray", f_type_str)) {
                f_type = .VarArray;
            }

            if (f_type != .FixedArray and f_type != .VarArray) {
                // Check if it's a user type
                for (ir.sym_tab.items, 0..) |s, i| {
                    if (std.mem.eql(u8, s.name, f_type_str)) {
                        if (s.type == .UserType) {
                            f_type = .User;
                        }

                        type_index = @intCast(i);
                        break;
                    }
                }
            } else {
                // Check type index for FixedArray and VarArray
                const type_str = self.source.get_token_text_by_idx(f.values[1]);

                type_index = for (ir.sym_tab.items, 0..) |s, i| {
                    if (std.mem.eql(u8, s.name, type_str)) {
                        break @intCast(i);
                    }
                } else {
                    self.print_error(self.source.tokens[f.values[1]], "Array Type not found!");
                    return error.SemanticTypeNotFound;
                };

                const extra_str = self.source.get_token_text_by_idx(f.values[2]);
                if (f_type == .FixedArray) {
                    extra_index = try std.fmt.parseInt(
                        u16,
                        extra_str,
                        0,
                    );
                } else {
                    extra_index = for (ir.sym_tab.items, 0..) |s, i| {
                        if (std.mem.eql(u8, s.name, extra_str)) {
                            break @intCast(i);
                        }
                    } else {
                        self.print_error(self.source.tokens[f.values[2]], "VarArray Size Type not found!");
                        return error.SemanticVarArraySizeTypeNotFound;
                    };
                }
            }

            try entries.append(.{
                .name = self.source.get_token_text_by_idx(f.name),
                .type = f_type,
                .value = type_index,
                .extra = extra_index,
            });
        }

        ir.add_to_struct_tab(.{
            .name = self.source.get_token_text_by_idx(e.name),
            .entries = try entries.toOwnedSlice(),
            .event = event,
            .event_id = event_id,
            .state_id = state_id,
            .direction = direction,
        }) catch {
            self.print_error(self.source.tokens[e.name], "Struct already exists!");
            return error.SemanticStructAlreadyExists;
        };
    }
}

pub fn analyze(self: *Self) !IR {
    var ir = try IR.init(self.source);
    ir.endian = self.ast.endian;

    // Build the symbol table
    try self.add_state_symbols(&ir);
    try self.add_struct_symbols(&ir);

    // Add enums to the symbol table
    try self.add_enums(&ir);

    // Build the struct table
    try self.add_structs(&ir);

    return ir;
}
