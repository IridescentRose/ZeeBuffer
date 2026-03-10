const std = @import("std");
const parser_mod = @import("parser.zig");
const Ast = parser_mod.Ast;

// ── Primitive types ───────────────────────────────────────────────────────────
// Integers, floats, and varint. These are the leaf types — they have no
// children and their wire size is always known statically (except varint,
// which is bounded to 1–5 bytes).

pub const PrimitiveType = enum {
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
    bool,
    varint,
};

// ── Array sizing ──────────────────────────────────────────────────────────────
// A fixed array carries its element count as a comptime-known integer.
// A prefixed array carries the type of the length prefix on the wire.
// Only unsigned integers and varint are valid prefix types — enforced in sema.

pub const PrefixType = enum { u8, u16, u32, varint };

pub const ArraySize = union(enum) {
    fixed: u32, // [T; 32]
    prefix: PrefixType, // [T; u16], [T; varint]
};

// ── Element types ─────────────────────────────────────────────────────────────
// What can legally appear as the element of an array.
// Notably absent: another array — nested arrays are not permitted.

pub const ElementType = union(enum) {
    primitive: PrimitiveType,
    enum_ref: *Enum,
    struct_ref: *Struct,
};

// ── Field types ───────────────────────────────────────────────────────────────
// The full set of types that can appear on a struct or packet field.
// Arrays are only valid here — not as array elements.

pub const FieldType = union(enum) {
    primitive: PrimitiveType,
    enum_ref: *Enum,
    struct_ref: *Struct,
    array: struct {
        element: ElementType,
        size: ArraySize,
    },
};

// ── Direction ─────────────────────────────────────────────────────────────────

pub const Direction = enum { client, server, both };

// ── Declarations ──────────────────────────────────────────────────────────────

pub const Field = struct {
    name: []const u8, // sliced directly from source, no copy
    type: FieldType,
};

pub const EnumVariant = struct {
    name: []const u8,
    value: u32,
};

pub const Enum = struct {
    name: []const u8,
    backing: PrimitiveType, // sema guarantees this is an unsigned integer type
    variants: []EnumVariant,
};

pub const Struct = struct {
    name: []const u8,
    fields: []Field,
};

pub const State = struct {
    name: []const u8,
    value: u32,
};

pub const Packet = struct {
    name: []const u8,
    state: *State,
    id: u32,
    direction: Direction,
    fields: []Field,
};

// ── Protocol config ───────────────────────────────────────────────────────────

pub const Endian = enum { big, little };

pub const Protocol = struct {
    name: []const u8,
    endian: Endian,
    version: u32,
};

// ── Program ───────────────────────────────────────────────────────────────────
// The root IR node. Owns all memory via the arena allocator.
// Declaration order within each slice matches source order — important for
// deterministic codegen output.

pub const Program = struct {
    arena: std.heap.ArenaAllocator, // owns all IR memory
    protocol: Protocol,
    states: []State,
    enums: []Enum,
    structs: []Struct,
    packets: []Packet,

    /// Validates semantic rules on a lowered IR Program that cannot be enforced
    /// by the type system or the lowering pass alone.
    pub fn verify(program: *const Program) !void {

        // ── States ────────────────────────────────────────────────────────────
        if (program.states.len == 0) return error.EmptyStatesBlock;

        // ── Program-level: enum/struct names share one namespace ──────────────
        for (program.enums, 0..) |e, ei| {
            // Enum name vs later enums
            for (program.enums[ei + 1 ..]) |e2| {
                if (std.mem.eql(u8, e.name, e2.name)) return error.DuplicateTypeName;
            }
            // Enum name vs all struct names
            for (program.structs) |s| {
                if (std.mem.eql(u8, e.name, s.name)) return error.DuplicateTypeName;
            }
        }
        // Struct name vs later structs (enum vs struct already covered above)
        for (program.structs, 0..) |s, si| {
            for (program.structs[si + 1 ..]) |s2| {
                if (std.mem.eql(u8, s.name, s2.name)) return error.DuplicateTypeName;
            }
        }

        // ── Enums ─────────────────────────────────────────────────────────────
        for (program.enums) |e| {
            if (!isUnsignedInt(e.backing)) return error.InvalidEnumBackingType;
            if (e.variants.len == 0) return error.EmptyEnum;
            for (e.variants, 0..) |v, vi| {
                for (e.variants[vi + 1 ..]) |v2| {
                    if (std.mem.eql(u8, v.name, v2.name)) return error.DuplicateVariantName;
                    if (v.value == v2.value) return error.DuplicateVariantValue;
                }
            }
        }

        // ── Structs ───────────────────────────────────────────────────────────
        for (program.structs) |s| {
            if (s.fields.len == 0) return error.EmptyStruct;
            for (s.fields, 0..) |f, fi| {
                for (s.fields[fi + 1 ..]) |f2| {
                    if (std.mem.eql(u8, f.name, f2.name)) return error.DuplicateFieldName;
                }
                try verifyField(f);
            }
        }

        // ── Packets ───────────────────────────────────────────────────────────
        for (program.packets, 0..) |pkt, pi| {
            // Duplicate field names
            for (pkt.fields, 0..) |f, fi| {
                for (pkt.fields[fi + 1 ..]) |f2| {
                    if (std.mem.eql(u8, f.name, f2.name)) return error.DuplicateFieldName;
                }
                try verifyField(f);
            }
            // Duplicate packet ID within the same state+direction pair
            for (program.packets[pi + 1 ..]) |pkt2| {
                if (pkt.state == pkt2.state and
                    pkt.direction == pkt2.direction and
                    pkt.id == pkt2.id)
                {
                    return error.DuplicatePacketID;
                }
            }
        }
    }
};

// ── Verify helpers ────────────────────────────────────────────────────────────

/// Valid enum backing types per the spec: unsigned integers only.
fn isUnsignedInt(p: PrimitiveType) bool {
    return switch (p) {
        .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

/// Validate a single field's type for rules that apply to both structs and
/// packets: varint-as-standalone and all array constraints.
fn verifyField(f: Field) !void {
    switch (f.type) {
        .primitive => |p| {
            if (p == .varint) return error.VarintNotAllowedAsFieldType;
        },
        .array => |arr| {
            switch (arr.size) {
                .fixed => |n| if (n == 0) return error.ZeroLengthArray,
                // All PrefixType variants (u8, u16, u32, varint) are valid by
                // construction — InvalidArrayPrefixType cannot be reached.
                .prefix => {},
            }
            switch (arr.element) {
                .primitive => |p| {
                    if (p == .varint) return error.VarintNotAllowedAsElementType;
                    if (p == .bool) return error.BoolNotAllowedAsElementType;
                },
                .enum_ref, .struct_ref => {},
            }
        },
        .enum_ref, .struct_ref => {},
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const PrimitiveMap = std.StaticStringMap(PrimitiveType);
const primitive_entries = .{
    .{ "u8", PrimitiveType.u8 },
    .{ "u16", PrimitiveType.u16 },
    .{ "u32", PrimitiveType.u32 },
    .{ "u64", PrimitiveType.u64 },
    .{ "i8", PrimitiveType.i8 },
    .{ "i16", PrimitiveType.i16 },
    .{ "i32", PrimitiveType.i32 },
    .{ "i64", PrimitiveType.i64 },
    .{ "f32", PrimitiveType.f32 },
    .{ "f64", PrimitiveType.f64 },
    .{ "bool", PrimitiveType.bool },
    .{ "varint", PrimitiveType.varint },
};

fn parsePrimitive(name: []const u8) ?PrimitiveType {
    return PrimitiveMap.initComptime(primitive_entries).get(name);
}

const PrefixMap = std.StaticStringMap(PrefixType);
const prefix_entries = .{
    .{ "u8", PrefixType.u8 },
    .{ "u16", PrefixType.u16 },
    .{ "u32", PrefixType.u32 },
    .{ "varint", PrefixType.varint },
};

fn parsePrefixType(name: []const u8) ?PrefixType {
    return PrefixMap.initComptime(prefix_entries).get(name);
}

fn parseDirection(name: []const u8) ?Direction {
    if (std.mem.eql(u8, name, "Client")) return .client;
    if (std.mem.eql(u8, name, "Server")) return .server;
    if (std.mem.eql(u8, name, "Both")) return .both;
    return null;
}

fn parseEndian(name: []const u8) ?Endian {
    if (std.mem.eql(u8, name, "big")) return .big;
    if (std.mem.eql(u8, name, "little")) return .little;
    return null;
}

/// Parses a decimal or 0x-prefixed hex integer token text into a u32.
fn parseIntLiteral(text: []const u8) !u32 {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        return std.fmt.parseInt(u32, text[2..], 16);
    }
    return std.fmt.parseInt(u32, text, 10);
}

/// Resolve a named type to a FieldType. Tries primitives first, then enums,
/// then structs. Returns error.UnknownType if the name is unrecognised.
fn resolveNamedAsField(
    name: []const u8,
    enum_map: *const std.StringHashMap(*Enum),
    struct_map: *const std.StringHashMap(*Struct),
) !FieldType {
    if (parsePrimitive(name)) |p| return .{ .primitive = p };
    if (enum_map.get(name)) |e| return .{ .enum_ref = e };
    if (struct_map.get(name)) |s| return .{ .struct_ref = s };
    return error.UnknownType;
}

/// Same resolution as resolveNamedAsField but returns an ElementType (used
/// for the element slot of an array — arrays of arrays are excluded by type).
fn resolveNamedAsElement(
    name: []const u8,
    enum_map: *const std.StringHashMap(*Enum),
    struct_map: *const std.StringHashMap(*Struct),
) !ElementType {
    if (parsePrimitive(name)) |p| return .{ .primitive = p };
    if (enum_map.get(name)) |e| return .{ .enum_ref = e };
    if (struct_map.get(name)) |s| return .{ .struct_ref = s };
    return error.UnknownType;
}

fn resolveTypeExpr(
    type_expr: parser_mod.TypeExpr,
    ast: *const Ast,
    enum_map: *const std.StringHashMap(*Enum),
    struct_map: *const std.StringHashMap(*Struct),
) !FieldType {
    switch (type_expr) {
        .named => |idx| return resolveNamedAsField(ast.tokenText(idx), enum_map, struct_map),
        .array => |arr| {
            const element = try resolveNamedAsElement(ast.tokenText(arr.element), enum_map, struct_map);
            const size_text = ast.tokenText(arr.size_token);
            // If the size token text is a recognised prefix type, it is a
            // prefix array; otherwise parse it as a decimal/hex integer.
            const size: ArraySize = if (parsePrefixType(size_text)) |pt|
                .{ .prefix = pt }
            else
                .{ .fixed = try parseIntLiteral(size_text) };
            return .{ .array = .{ .element = element, .size = size } };
        },
    }
}

fn resolveFields(
    field_decls: []const parser_mod.FieldDecl,
    ast: *const Ast,
    enum_map: *const std.StringHashMap(*Enum),
    struct_map: *const std.StringHashMap(*Struct),
    aa: std.mem.Allocator,
) ![]Field {
    const fields = try aa.alloc(Field, field_decls.len);
    for (field_decls, 0..) |fd, i| {
        fields[i] = .{
            .name = ast.tokenText(fd.name),
            .type = try resolveTypeExpr(fd.type, ast, enum_map, struct_map),
        };
    }
    return fields;
}

// ── Entry point ───────────────────────────────────────────────────────────────

/// Transforms a parsed AST into a resolved IR Program.
///
/// Name resolution is performed in two passes: the first pass registers all
/// declared enum, struct, and state names into lookup tables; the second pass
/// walks all declarations and resolves every type reference and name to its
/// concrete IR counterpart. This two-pass approach allows forward references —
/// a packet may reference a struct declared later in the file.
///
/// All IR memory is owned by the returned Program's arena allocator. The
/// caller must ensure the source buffer and AST outlive this call, as name
/// strings are sliced directly from source rather than copied.
///
/// Lowering does not perform any validation beyond name resolution. The caller
/// should validate the resulting IR before use.
///
/// Returns the first error encountered. On error, a diagnostic with source
/// location is written to stderr before returning.
pub fn lower(allocator: std.mem.Allocator, ast: *Ast) !Program {
    // Initialise the arena first so that program.arena.allocator() returns a
    // pointer stable for the lifetime of the program value.
    var program: Program = undefined;
    program.arena = std.heap.ArenaAllocator.init(allocator);
    errdefer program.arena.deinit();
    const aa = program.arena.allocator();

    // Temporary lookup tables — use the backing allocator so they are freed
    // before the function returns regardless of success or failure.
    var enum_map = std.StringHashMap(*Enum).init(allocator);
    defer enum_map.deinit();
    var struct_map = std.StringHashMap(*Struct).init(allocator);
    defer struct_map.deinit();
    var state_map = std.StringHashMap(*State).init(allocator);
    defer state_map.deinit();

    // ── Protocol config ───────────────────────────────────────────────────────
    {
        var endian: Endian = .big;
        var version: u32 = 0;
        for (ast.file.protocol.entries) |kv| {
            const key = ast.tokenText(kv.key);
            const val = ast.tokenText(kv.value);
            if (std.mem.eql(u8, key, "endian")) {
                endian = parseEndian(val) orelse return error.UnknownEndian;
            } else if (std.mem.eql(u8, key, "version")) {
                version = try parseIntLiteral(val);
            }
        }
        program.protocol = .{
            .name = ast.tokenText(ast.file.protocol.name),
            .endian = endian,
            .version = version,
        };
    }

    // ── States ────────────────────────────────────────────────────────────────
    {
        const entries = ast.file.states.entries;
        const states = try aa.alloc(State, entries.len);
        for (entries, 0..) |entry, i| {
            states[i] = .{
                .name = ast.tokenText(entry.name),
                .value = try parseIntLiteral(ast.tokenText(entry.value)),
            };
            try state_map.put(states[i].name, &states[i]);
        }
        program.states = states;
    }

    // ── Pass 1: register names ────────────────────────────────────────────────
    // Pre-allocate stable arena slots for every enum and struct so that
    // pointers stored in the lookup maps remain valid through pass 2.
    // Enum variants are fully resolved here (no type references needed).
    // Struct fields are left undefined and filled in pass 2.
    {
        var enum_count: usize = 0;
        var struct_count: usize = 0;
        var packet_count: usize = 0;
        for (ast.nodes) |node| switch (node) {
            .@"enum" => enum_count += 1,
            .@"struct" => struct_count += 1,
            .packet => packet_count += 1,
        };

        program.enums = try aa.alloc(Enum, enum_count);
        program.structs = try aa.alloc(Struct, struct_count);
        program.packets = try aa.alloc(Packet, packet_count);

        var ei: usize = 0;
        var si: usize = 0;
        for (ast.nodes) |node| {
            switch (node) {
                .@"enum" => |e| {
                    const backing = parsePrimitive(ast.tokenText(e.backing)) orelse
                        return error.UnknownType;
                    const variants = try aa.alloc(EnumVariant, e.variants.len);
                    for (e.variants, 0..) |v, vi| {
                        variants[vi] = .{
                            .name = ast.tokenText(v.name),
                            .value = try parseIntLiteral(ast.tokenText(v.value)),
                        };
                    }
                    program.enums[ei] = .{
                        .name = ast.tokenText(e.name),
                        .backing = backing,
                        .variants = variants,
                    };
                    try enum_map.put(program.enums[ei].name, &program.enums[ei]);
                    ei += 1;
                },
                .@"struct" => |s| {
                    program.structs[si] = .{
                        .name = ast.tokenText(s.name),
                        .fields = undefined, // resolved in pass 2
                    };
                    try struct_map.put(program.structs[si].name, &program.structs[si]);
                    si += 1;
                },
                .packet => {},
            }
        }
    }

    // ── Pass 2: resolve types ─────────────────────────────────────────────────
    // All names are now registered. Walk the nodes again to resolve field
    // types and fully build packets.
    {
        var si: usize = 0;
        var pi: usize = 0;
        for (ast.nodes) |node| {
            switch (node) {
                .@"enum" => {},
                .@"struct" => |s| {
                    program.structs[si].fields = try resolveFields(
                        s.fields,
                        ast,
                        &enum_map,
                        &struct_map,
                        aa,
                    );
                    si += 1;
                },
                .packet => |pkt| {
                    const state_name = ast.tokenText(pkt.state);
                    const state_ptr = state_map.get(state_name) orelse return error.UnknownState;

                    const direction_name = ast.tokenText(pkt.direction);
                    const direction = parseDirection(direction_name) orelse return error.UnknownDirection;

                    program.packets[pi] = .{
                        .name = ast.tokenText(pkt.name),
                        .state = state_ptr,
                        .id = try parseIntLiteral(ast.tokenText(pkt.id)),
                        .direction = direction,
                        .fields = try resolveFields(pkt.fields, ast, &enum_map, &struct_map, aa),
                    };
                    pi += 1;
                },
            }
        }
    }

    return program;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

/// Lex → parse → lower a source string. Uses an arena for the parse phase
/// so the caller only needs to manage `prog.arena.deinit()`.
fn testLower(src: []const u8, ir_alloc: std.mem.Allocator) !Program {
    var parse_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer parse_arena.deinit();
    const pa = parse_arena.allocator();
    const toks = try @import("lexer.zig").tokenize(pa, src);
    var ast = try parser_mod.parse(pa, toks, src);
    return lower(ir_alloc, &ast);
}

test "protocol: name, endian big, version" {
    var prog = try testLower(
        "protocol MyProto { endian: big, version: 3, } states { S = 0, }",
        testing.allocator,
    );
    defer prog.arena.deinit();

    try testing.expectEqualStrings("MyProto", prog.protocol.name);
    try testing.expectEqual(Endian.big, prog.protocol.endian);
    try testing.expectEqual(@as(u32, 3), prog.protocol.version);
}

test "protocol: endian little" {
    var prog = try testLower(
        "protocol P { endian: little, version: 0, } states { S = 0, }",
        testing.allocator,
    );
    defer prog.arena.deinit();
    try testing.expectEqual(Endian.little, prog.protocol.endian);
}

test "states: names and values" {
    var prog = try testLower(
        "protocol P { endian: big, } states { Handshake = 0, Login = 1, Play = 2, }",
        testing.allocator,
    );
    defer prog.arena.deinit();

    try testing.expectEqual(@as(usize, 3), prog.states.len);
    try testing.expectEqualStrings("Handshake", prog.states[0].name);
    try testing.expectEqual(@as(u32, 0), prog.states[0].value);
    try testing.expectEqualStrings("Login", prog.states[1].name);
    try testing.expectEqual(@as(u32, 1), prog.states[1].value);
    try testing.expectEqualStrings("Play", prog.states[2].name);
    try testing.expectEqual(@as(u32, 2), prog.states[2].value);
}

test "enum: backing type and variants" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum Color : u8 { Red = 1, Green = 2, Blue = 3, }
    , testing.allocator);
    defer prog.arena.deinit();

    try testing.expectEqual(@as(usize, 1), prog.enums.len);
    const e = prog.enums[0];
    try testing.expectEqualStrings("Color", e.name);
    try testing.expectEqual(PrimitiveType.u8, e.backing);
    try testing.expectEqual(@as(usize, 3), e.variants.len);
    try testing.expectEqualStrings("Red", e.variants[0].name);
    try testing.expectEqual(@as(u32, 1), e.variants[0].value);
    try testing.expectEqualStrings("Blue", e.variants[2].name);
    try testing.expectEqual(@as(u32, 3), e.variants[2].value);
}

test "struct: primitive fields" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Vec3 { x: f64, y: f64, z: f64, }
    , testing.allocator);
    defer prog.arena.deinit();

    const s = prog.structs[0];
    try testing.expectEqualStrings("Vec3", s.name);
    try testing.expectEqual(@as(usize, 3), s.fields.len);
    try testing.expectEqualStrings("x", s.fields[0].name);
    try testing.expectEqual(PrimitiveType.f64, s.fields[0].type.primitive);
    try testing.expectEqual(PrimitiveType.f64, s.fields[2].type.primitive);
}

test "struct: enum field resolves to enum_ref" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum Dir : u8 { N = 0, }
        \\struct Pose { facing: Dir, }
    , testing.allocator);
    defer prog.arena.deinit();

    const s = prog.structs[0];
    try testing.expectEqual(std.meta.Tag(FieldType).enum_ref, std.meta.activeTag(s.fields[0].type));
    try testing.expectEqualStrings("Dir", s.fields[0].type.enum_ref.name);
}

test "struct: embedded struct resolves to struct_ref" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Vec3 { x: f64, }
        \\struct AABB { min: Vec3, max: Vec3, }
    , testing.allocator);
    defer prog.arena.deinit();

    const aabb = prog.structs[1];
    try testing.expectEqualStrings("AABB", aabb.name);
    try testing.expectEqual(std.meta.Tag(FieldType).struct_ref, std.meta.activeTag(aabb.fields[0].type));
    try testing.expectEqualStrings("Vec3", aabb.fields[0].type.struct_ref.name);
}

test "struct: array field with fixed size" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Key { data: [u8; 32], }
    , testing.allocator);
    defer prog.arena.deinit();

    const f = prog.structs[0].fields[0];
    try testing.expectEqualStrings("data", f.name);
    try testing.expectEqual(PrimitiveType.u8, f.type.array.element.primitive);
    try testing.expectEqual(@as(u32, 32), f.type.array.size.fixed);
}

test "struct: array fields with prefix types" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Msg { a: [u8; u8], b: [u16; u16], c: [u8; u32], d: [u16; varint], }
    , testing.allocator);
    defer prog.arena.deinit();

    const fields = prog.structs[0].fields;
    try testing.expectEqual(PrefixType.u8, fields[0].type.array.size.prefix);
    try testing.expectEqual(PrefixType.u16, fields[1].type.array.size.prefix);
    try testing.expectEqual(PrefixType.u32, fields[2].type.array.size.prefix);
    try testing.expectEqual(PrefixType.varint, fields[3].type.array.size.prefix);
}

test "packet: state ref, direction, hex id, fields" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { Play = 3, }
        \\packet Move : Play[0x07] -> Server { entityId: u32, }
    , testing.allocator);
    defer prog.arena.deinit();

    try testing.expectEqual(@as(usize, 1), prog.packets.len);
    const pkt = prog.packets[0];
    try testing.expectEqualStrings("Move", pkt.name);
    try testing.expectEqualStrings("Play", pkt.state.name);
    try testing.expectEqual(@as(u32, 3), pkt.state.value);
    try testing.expectEqual(@as(u32, 0x07), pkt.id);
    try testing.expectEqual(Direction.server, pkt.direction);
    try testing.expectEqual(@as(usize, 1), pkt.fields.len);
    try testing.expectEqualStrings("entityId", pkt.fields[0].name);
    try testing.expectEqual(PrimitiveType.u32, pkt.fields[0].type.primitive);
}

test "packet: decimal id and Client direction" {
    var prog = try testLower(
        "protocol P { endian: big, } states { S = 0, } packet Ping : S[7] -> Client { }",
        testing.allocator,
    );
    defer prog.arena.deinit();

    try testing.expectEqual(@as(u32, 7), prog.packets[0].id);
    try testing.expectEqual(Direction.client, prog.packets[0].direction);
}

test "packet: Both direction" {
    var prog = try testLower(
        "protocol P { endian: big, } states { S = 0, } packet Sync : S[0x00] -> Both { }",
        testing.allocator,
    );
    defer prog.arena.deinit();

    try testing.expectEqual(Direction.both, prog.packets[0].direction);
}

test "forward reference: struct field references later-declared struct" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct B { a: A, }
        \\struct A { x: u8, }
    , testing.allocator);
    defer prog.arena.deinit();

    // B comes first in source, but its field resolves to A declared after it.
    const b = prog.structs[0];
    try testing.expectEqualStrings("B", b.name);
    try testing.expectEqual(std.meta.Tag(FieldType).struct_ref, std.meta.activeTag(b.fields[0].type));
    try testing.expectEqualStrings("A", b.fields[0].type.struct_ref.name);
}

test "multiple decl counts" {
    var prog = try testLower(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum E1 : u8 { A = 0, }
        \\enum E2 : u16 { B = 1, }
        \\struct S1 { x: u8, }
        \\packet Pkt1 : S[0x01] -> Server { }
        \\packet Pkt2 : S[0x02] -> Client { }
    , testing.allocator);
    defer prog.arena.deinit();

    try testing.expectEqual(@as(usize, 2), prog.enums.len);
    try testing.expectEqual(@as(usize, 1), prog.structs.len);
    try testing.expectEqual(@as(usize, 2), prog.packets.len);
}

test "error: unknown field type" {
    try testing.expectError(error.UnknownType, testLower(
        "protocol P { endian: big, } states { S = 0, } struct V { x: Bogus, }",
        testing.allocator,
    ));
}

test "error: unknown state in packet" {
    try testing.expectError(error.UnknownState, testLower(
        "protocol P { endian: big, } states { S = 0, } packet Foo : Ghost[0x01] -> Server { }",
        testing.allocator,
    ));
}

test "error: unknown direction" {
    try testing.expectError(error.UnknownDirection, testLower(
        "protocol P { endian: big, } states { S = 0, } packet Foo : S[0x01] -> Sideways { }",
        testing.allocator,
    ));
}

test "error: unknown endian value" {
    try testing.expectError(error.UnknownEndian, testLower(
        "protocol P { endian: diagonal, } states { S = 0, }",
        testing.allocator,
    ));
}

// ── verify() tests ────────────────────────────────────────────────────────────

/// Lower + verify in one call. Returns the error from either step.
fn testVerify(src: []const u8) !void {
    var parse_arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer parse_arena.deinit();
    const pa = parse_arena.allocator();
    const toks = try @import("lexer.zig").tokenize(pa, src);
    var ast = try parser_mod.parse(pa, toks, src);
    var prog = try lower(testing.allocator, &ast);
    defer prog.arena.deinit();
    return prog.verify();
}

test "verify: valid program passes" {
    try testVerify(
        \\protocol P { endian: big, version: 1, }
        \\states { Handshake = 0, Play = 1, }
        \\enum Dir : u8 { N = 0, E = 1, S = 2, W = 3, }
        \\struct Vec3 { x: f64, y: f64, z: f64, }
        \\packet Move : Play[0x01] -> Server { pos: Vec3, facing: Dir, data: [u8; u16], key: [u8; 32], }
        \\packet Move : Play[0x01] -> Client { pos: Vec3, }
    );
}

// ── States ────────────────────────────────────────────────────────────────────

test "verify: empty states block" {
    try testing.expectError(error.EmptyStatesBlock, testVerify(
        "protocol P { endian: big, } states { }",
    ));
}

// ── Enums ─────────────────────────────────────────────────────────────────────

test "verify: invalid enum backing type (signed int)" {
    try testing.expectError(error.InvalidEnumBackingType, testVerify(
        "protocol P { endian: big, } states { S = 0, } enum E : i8 { A = 0, }",
    ));
}

test "verify: invalid enum backing type (float)" {
    try testing.expectError(error.InvalidEnumBackingType, testVerify(
        "protocol P { endian: big, } states { S = 0, } enum E : f32 { A = 0, }",
    ));
}

test "verify: invalid enum backing type (bool)" {
    try testing.expectError(error.InvalidEnumBackingType, testVerify(
        "protocol P { endian: big, } states { S = 0, } enum E : bool { A = 0, }",
    ));
}

test "verify: empty enum" {
    try testing.expectError(error.EmptyEnum, testVerify(
        "protocol P { endian: big, } states { S = 0, } enum E : u8 { }",
    ));
}

test "verify: duplicate variant name" {
    try testing.expectError(error.DuplicateVariantName, testVerify(
        "protocol P { endian: big, } states { S = 0, } enum E : u8 { A = 1, A = 2, }",
    ));
}

test "verify: duplicate variant value" {
    try testing.expectError(error.DuplicateVariantValue, testVerify(
        "protocol P { endian: big, } states { S = 0, } enum E : u8 { A = 1, B = 1, }",
    ));
}

// ── Structs ───────────────────────────────────────────────────────────────────

test "verify: empty struct" {
    try testing.expectError(error.EmptyStruct, testVerify(
        "protocol P { endian: big, } states { S = 0, } struct V { }",
    ));
}

test "verify: duplicate field name in struct" {
    try testing.expectError(error.DuplicateFieldName, testVerify(
        "protocol P { endian: big, } states { S = 0, } struct V { x: u8, x: u16, }",
    ));
}

test "verify: varint as standalone struct field type" {
    try testing.expectError(error.VarintNotAllowedAsFieldType, testVerify(
        "protocol P { endian: big, } states { S = 0, } struct V { n: varint, }",
    ));
}

// ── Packets ───────────────────────────────────────────────────────────────────

test "verify: duplicate field name in packet" {
    try testing.expectError(error.DuplicateFieldName, testVerify(
        "protocol P { endian: big, } states { S = 0, } packet Foo : S[0x01] -> Server { x: u8, x: u16, }",
    ));
}

test "verify: varint as standalone packet field type" {
    try testing.expectError(error.VarintNotAllowedAsFieldType, testVerify(
        "protocol P { endian: big, } states { S = 0, } packet Foo : S[0x01] -> Server { n: varint, }",
    ));
}

test "verify: duplicate packet ID same state and direction" {
    try testing.expectError(error.DuplicatePacketID, testVerify(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\packet A : S[0x01] -> Server { }
        \\packet B : S[0x01] -> Server { }
    ));
}

test "verify: same ID different direction is allowed" {
    // Handshake[0x00]->Server and Handshake[0x00]->Client must not conflict.
    try testVerify(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\packet A : S[0x01] -> Server { }
        \\packet B : S[0x01] -> Client { }
    );
}

test "verify: same ID different state is allowed" {
    try testVerify(
        \\protocol P { endian: big, }
        \\states { Handshake = 0, Play = 1, }
        \\packet A : Handshake[0x01] -> Server { }
        \\packet B : Play[0x01] -> Server { }
    );
}

// ── Arrays ────────────────────────────────────────────────────────────────────

test "verify: zero-length fixed array" {
    try testing.expectError(error.ZeroLengthArray, testVerify(
        "protocol P { endian: big, } states { S = 0, } struct V { data: [u8; 0], }",
    ));
}

test "verify: varint as array element type" {
    try testing.expectError(error.VarintNotAllowedAsElementType, testVerify(
        "protocol P { endian: big, } states { S = 0, } struct V { data: [varint; u8], }",
    ));
}

test "verify: bool as array element type" {
    try testing.expectError(error.BoolNotAllowedAsElementType, testVerify(
        "protocol P { endian: big, } states { S = 0, } struct V { flags: [bool; u16], }",
    ));
}

// ── Program-level ─────────────────────────────────────────────────────────────

test "verify: duplicate type name (enum and struct)" {
    try testing.expectError(error.DuplicateTypeName, testVerify(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum Foo : u8 { A = 0, }
        \\struct Foo { x: u8, }
    ));
}

test "verify: duplicate type name (two enums)" {
    try testing.expectError(error.DuplicateTypeName, testVerify(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum Foo : u8 { A = 0, }
        \\enum Foo : u16 { B = 1, }
    ));
}

test "verify: duplicate type name (two structs)" {
    try testing.expectError(error.DuplicateTypeName, testVerify(
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Foo { x: u8, }
        \\struct Foo { y: u16, }
    ));
}
