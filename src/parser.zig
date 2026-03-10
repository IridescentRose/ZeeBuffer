const std = @import("std");
const lexer = @import("lexer.zig");

pub const Token = lexer.Token;
const TokenKind = lexer.TokenKind;

pub const TokenIndex = u16;
pub const NodeIndex = u16;

pub const NULL_NODE: NodeIndex = std.math.maxInt(u16); // 0xFFFF sentinel

// ── Root ──────────────────────────────────────────────────────────────────────
// A file is only valid if it has exactly one protocol block and one states
// block. Enums, structs, and packets are the variable parts.

pub const File = struct {
    protocol: ProtocolDecl,
    states: StatesDecl,
    decls: []NodeIndex,
};

// ── Protocol and States — required, exactly once ──────────────────────────────

pub const ProtocolDecl = struct {
    name: TokenIndex,
    entries: []KeyValue,
};

pub const KeyValue = struct {
    key: TokenIndex,
    value: TokenIndex,
};

pub const StatesDecl = struct {
    entries: []StateEntry,
};

pub const StateEntry = struct {
    name: TokenIndex,
    value: TokenIndex,
};

// ── Declarations — optional, any number ───────────────────────────────────────

pub const Node = union(enum) {
    @"enum": EnumDecl,
    @"struct": StructDecl,
    packet: PacketDecl,
};

pub const EnumDecl = struct {
    name: TokenIndex,
    backing: TokenIndex,
    variants: []EnumVariant,
};

pub const EnumVariant = struct {
    name: TokenIndex,
    value: TokenIndex,
};

pub const StructDecl = struct {
    name: TokenIndex,
    fields: []FieldDecl,
};

pub const PacketDecl = struct {
    name: TokenIndex,
    state: TokenIndex,
    id: TokenIndex,
    direction: TokenIndex,
    fields: []FieldDecl,
};

// ── Fields and types ──────────────────────────────────────────────────────────

pub const FieldDecl = struct {
    name: TokenIndex,
    type: TypeExpr,
};

pub const TypeExpr = union(enum) {
    named: TokenIndex,
    array: ArrayTypeExpr,
};

pub const ArrayTypeExpr = struct {
    element: TokenIndex, // always a named type (primitive, struct, or enum)
    size_token: TokenIndex,
};

// ── Ast ───────────────────────────────────────────────────────────────────────

pub const Ast = struct {
    source: []const u8,
    tokens: []const Token,
    nodes: []Node,
    file: File,

    pub fn tokenText(ast: *const Ast, idx: TokenIndex) []const u8 {
        const tok = ast.tokens[idx];
        return ast.source[tok.start..][0..tok.len];
    }
};

// ── Parser ────────────────────────────────────────────────────────────────────

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const Token,
    pos: TokenIndex,

    fn peekKind(p: *const Parser) TokenKind {
        if (p.pos >= p.tokens.len) return .eof;
        return p.tokens[p.pos].kind;
    }

    fn advance(p: *Parser) TokenIndex {
        const idx = p.pos;
        p.pos += 1;
        return idx;
    }

    /// Consume and return the current token index, or error if kind doesn't match.
    fn eat(p: *Parser, kind: TokenKind) !TokenIndex {
        if (p.peekKind() != kind) return error.UnexpectedToken;
        return p.advance();
    }

    // ── protocol_decl ─────────────────────────────────────────────────────────
    // "protocol" IDENTIFIER "{" { key_value "," } "}"

    fn parseProtocolDecl(p: *Parser) !ProtocolDecl {
        _ = try p.eat(.kw_protocol);
        const name = try p.eat(.identifier);
        _ = try p.eat(.l_brace);

        var entries = try std.ArrayList(KeyValue).initCapacity(p.allocator, 4);
        errdefer entries.deinit(p.allocator);

        while (p.peekKind() != .r_brace) {
            const key = try p.eat(.identifier);
            _ = try p.eat(.colon);
            // value is either an identifier (e.g. "big") or an integer (e.g. 1)
            const value: TokenIndex = switch (p.peekKind()) {
                .identifier, .int_literal => p.advance(),
                else => return error.UnexpectedToken,
            };
            _ = try p.eat(.comma);
            try entries.append(p.allocator, .{ .key = key, .value = value });
        }

        _ = try p.eat(.r_brace);
        return .{ .name = name, .entries = try entries.toOwnedSlice(p.allocator) };
    }

    // ── states_decl ───────────────────────────────────────────────────────────
    // "states" "{" { IDENTIFIER "=" INT_LITERAL "," } "}"

    fn parseStatesDecl(p: *Parser) !StatesDecl {
        _ = try p.eat(.kw_states);
        _ = try p.eat(.l_brace);

        var entries = try std.ArrayList(StateEntry).initCapacity(p.allocator, 4);
        errdefer entries.deinit(p.allocator);

        while (p.peekKind() != .r_brace) {
            const name = try p.eat(.identifier);
            _ = try p.eat(.equals);
            const value = try p.eat(.int_literal);
            _ = try p.eat(.comma);
            try entries.append(p.allocator, .{ .name = name, .value = value });
        }

        _ = try p.eat(.r_brace);
        return .{ .entries = try entries.toOwnedSlice(p.allocator) };
    }

    // ── decl ──────────────────────────────────────────────────────────────────

    fn parseDecl(p: *Parser) !Node {
        return switch (p.peekKind()) {
            .kw_enum => .{ .@"enum" = try p.parseEnumDecl() },
            .kw_struct => .{ .@"struct" = try p.parseStructDecl() },
            .kw_packet => .{ .packet = try p.parsePacketDecl() },
            else => error.UnexpectedToken,
        };
    }

    // ── enum_decl ─────────────────────────────────────────────────────────────
    // "enum" IDENTIFIER ":" IDENTIFIER "{" { IDENTIFIER "=" INT_LITERAL "," } "}"

    fn parseEnumDecl(p: *Parser) !EnumDecl {
        _ = try p.eat(.kw_enum);
        const name = try p.eat(.identifier);
        _ = try p.eat(.colon);
        const backing = try p.eat(.identifier);
        _ = try p.eat(.l_brace);

        var variants = try std.ArrayList(EnumVariant).initCapacity(p.allocator, 4);
        errdefer variants.deinit(p.allocator);

        while (p.peekKind() != .r_brace) {
            const vname = try p.eat(.identifier);
            _ = try p.eat(.equals);
            const vvalue = try p.eat(.int_literal);
            _ = try p.eat(.comma);
            try variants.append(p.allocator, .{ .name = vname, .value = vvalue });
        }

        _ = try p.eat(.r_brace);
        return .{ .name = name, .backing = backing, .variants = try variants.toOwnedSlice(p.allocator) };
    }

    // ── struct_decl ───────────────────────────────────────────────────────────
    // "struct" IDENTIFIER "{" { field_decl "," } "}"

    fn parseStructDecl(p: *Parser) !StructDecl {
        _ = try p.eat(.kw_struct);
        const name = try p.eat(.identifier);
        _ = try p.eat(.l_brace);
        const fields = try p.parseFields();
        _ = try p.eat(.r_brace);
        return .{ .name = name, .fields = fields };
    }

    // ── packet_decl ───────────────────────────────────────────────────────────
    // "packet" IDENTIFIER ":" IDENTIFIER "[" INT_LITERAL "]" "->" IDENTIFIER
    //          "{" { field_decl "," } "}"

    fn parsePacketDecl(p: *Parser) !PacketDecl {
        _ = try p.eat(.kw_packet);
        const name = try p.eat(.identifier);
        _ = try p.eat(.colon);
        const state = try p.eat(.identifier);
        _ = try p.eat(.l_bracket);
        const id = try p.eat(.int_literal);
        _ = try p.eat(.r_bracket);
        _ = try p.eat(.arrow);
        const direction = try p.eat(.identifier);
        _ = try p.eat(.l_brace);
        const fields = try p.parseFields();
        _ = try p.eat(.r_brace);
        return .{ .name = name, .state = state, .id = id, .direction = direction, .fields = fields };
    }

    // ── field_decl ────────────────────────────────────────────────────────────
    // { IDENTIFIER ":" type_expr "," }  (reads until "}")

    fn parseFields(p: *Parser) ![]FieldDecl {
        var fields = try std.ArrayList(FieldDecl).initCapacity(p.allocator, 4);
        errdefer fields.deinit(p.allocator);

        while (p.peekKind() != .r_brace) {
            const name = try p.eat(.identifier);
            _ = try p.eat(.colon);
            const type_expr = try p.parseTypeExpr();
            _ = try p.eat(.comma);
            try fields.append(p.allocator, .{ .name = name, .type = type_expr });
        }

        return fields.toOwnedSlice(p.allocator);
    }

    // ── type_expr ─────────────────────────────────────────────────────────────
    // named_type = IDENTIFIER
    // array_type = "[" IDENTIFIER ";" (INT_LITERAL | IDENTIFIER) "]"

    fn parseTypeExpr(p: *Parser) !TypeExpr {
        if (p.peekKind() == .l_bracket) {
            _ = p.advance(); // consume "["
            const element = try p.eat(.identifier);
            _ = try p.eat(.semicolon);
            const size_token: TokenIndex = switch (p.peekKind()) {
                .int_literal, .identifier => p.advance(),
                else => return error.UnexpectedToken,
            };
            _ = try p.eat(.r_bracket);
            return .{ .array = .{ .element = element, .size_token = size_token } };
        }
        return .{ .named = try p.eat(.identifier) };
    }
};

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn parse(allocator: std.mem.Allocator, tokens: []Token, source: []const u8) !Ast {
    var node_list = try std.ArrayList(Node).initCapacity(allocator, 8);
    errdefer node_list.deinit(allocator);

    var decl_list = try std.ArrayList(NodeIndex).initCapacity(allocator, 8);
    errdefer decl_list.deinit(allocator);

    var p = Parser{
        .allocator = allocator,
        .source = source,
        .tokens = tokens,
        .pos = 0,
    };

    const protocol = try p.parseProtocolDecl();
    const states = try p.parseStatesDecl();

    while (p.peekKind() != .eof) {
        const node_idx: NodeIndex = @intCast(node_list.items.len);
        const node = try p.parseDecl();
        try node_list.append(allocator, node);
        try decl_list.append(allocator, node_idx);
    }

    return Ast{
        .source = source,
        .tokens = tokens,
        .nodes = try node_list.toOwnedSlice(allocator),
        .file = .{
            .protocol = protocol,
            .states = states,
            .decls = try decl_list.toOwnedSlice(allocator),
        },
    };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn testParse(arena: std.mem.Allocator, src: []const u8) !Ast {
    const toks = try lexer.tokenize(arena, src);
    return parse(arena, toks, src);
}

test "minimal file: protocol and states, no decls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "protocol P { endian: big, } states { Boot = 0, }";
    const ast = try testParse(a, src);

    try testing.expectEqualStrings("P", ast.tokenText(ast.file.protocol.name));
    try testing.expectEqual(@as(usize, 1), ast.file.protocol.entries.len);
    try testing.expectEqualStrings("endian", ast.tokenText(ast.file.protocol.entries[0].key));
    try testing.expectEqualStrings("big", ast.tokenText(ast.file.protocol.entries[0].value));

    try testing.expectEqual(@as(usize, 1), ast.file.states.entries.len);
    try testing.expectEqualStrings("Boot", ast.tokenText(ast.file.states.entries[0].name));
    try testing.expectEqualStrings("0", ast.tokenText(ast.file.states.entries[0].value));

    try testing.expectEqual(@as(usize, 0), ast.file.decls.len);
}

test "protocol: integer value entry" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "protocol P { version: 42, } states { S = 0, }";
    const ast = try testParse(arena.allocator(), src);

    try testing.expectEqual(@as(usize, 1), ast.file.protocol.entries.len);
    try testing.expectEqualStrings("version", ast.tokenText(ast.file.protocol.entries[0].key));
    try testing.expectEqualStrings("42", ast.tokenText(ast.file.protocol.entries[0].value));
}

test "protocol: multiple entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "protocol P { endian: big, version: 1, } states { S = 0, }";
    const ast = try testParse(arena.allocator(), src);

    try testing.expectEqual(@as(usize, 2), ast.file.protocol.entries.len);
    try testing.expectEqualStrings("endian", ast.tokenText(ast.file.protocol.entries[0].key));
    try testing.expectEqualStrings("version", ast.tokenText(ast.file.protocol.entries[1].key));
    try testing.expectEqualStrings("1", ast.tokenText(ast.file.protocol.entries[1].value));
}

test "states: multiple entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "protocol P { endian: big, } states { Handshake = 0, Login = 1, Play = 2, }";
    const ast = try testParse(arena.allocator(), src);

    try testing.expectEqual(@as(usize, 3), ast.file.states.entries.len);
    try testing.expectEqualStrings("Handshake", ast.tokenText(ast.file.states.entries[0].name));
    try testing.expectEqualStrings("0", ast.tokenText(ast.file.states.entries[0].value));
    try testing.expectEqualStrings("Login", ast.tokenText(ast.file.states.entries[1].name));
    try testing.expectEqualStrings("Play", ast.tokenText(ast.file.states.entries[2].name));
    try testing.expectEqualStrings("2", ast.tokenText(ast.file.states.entries[2].value));
}

test "enum decl: name, backing type, variants" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src =
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum Color : u8 { Red = 1, Green = 2, Blue = 3, }
    ;
    const ast = try testParse(arena.allocator(), src);

    try testing.expectEqual(@as(usize, 1), ast.file.decls.len);
    const node = ast.nodes[ast.file.decls[0]];
    try testing.expectEqual(std.meta.Tag(Node).@"enum", std.meta.activeTag(node));

    const e = node.@"enum";
    try testing.expectEqualStrings("Color", ast.tokenText(e.name));
    try testing.expectEqualStrings("u8", ast.tokenText(e.backing));
    try testing.expectEqual(@as(usize, 3), e.variants.len);
    try testing.expectEqualStrings("Red", ast.tokenText(e.variants[0].name));
    try testing.expectEqualStrings("1", ast.tokenText(e.variants[0].value));
    try testing.expectEqualStrings("Blue", ast.tokenText(e.variants[2].name));
    try testing.expectEqualStrings("3", ast.tokenText(e.variants[2].value));
}

test "struct decl: named fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src =
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Vec3 { x: f64, y: f64, z: f64, }
    ;
    const ast = try testParse(arena.allocator(), src);

    const node = ast.nodes[ast.file.decls[0]];
    const s = node.@"struct";
    try testing.expectEqualStrings("Vec3", ast.tokenText(s.name));
    try testing.expectEqual(@as(usize, 3), s.fields.len);
    try testing.expectEqualStrings("x", ast.tokenText(s.fields[0].name));
    try testing.expectEqualStrings("f64", ast.tokenText(s.fields[0].type.named));
    try testing.expectEqualStrings("z", ast.tokenText(s.fields[2].name));
}

test "struct decl: array fields with identifier and int size spec" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src =
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\struct Data { name: [u8; u8], key: [u8; 32], data: [u16; varint], }
    ;
    const ast = try testParse(arena.allocator(), src);

    const s = ast.nodes[ast.file.decls[0]].@"struct";
    try testing.expectEqual(@as(usize, 3), s.fields.len);

    // [u8; u8] — identifier size spec
    const name_field = s.fields[0];
    try testing.expectEqualStrings("name", ast.tokenText(name_field.name));
    try testing.expectEqualStrings("u8", ast.tokenText(name_field.type.array.element));
    try testing.expectEqualStrings("u8", ast.tokenText(name_field.type.array.size_token));

    // [u8; 32] — int literal size spec
    const key_field = s.fields[1];
    try testing.expectEqualStrings("key", ast.tokenText(key_field.name));
    try testing.expectEqualStrings("u8", ast.tokenText(key_field.type.array.element));
    try testing.expectEqualStrings("32", ast.tokenText(key_field.type.array.size_token));

    // [u16; varint] — varint identifier size spec
    const data_field = s.fields[2];
    try testing.expectEqualStrings("varint", ast.tokenText(data_field.type.array.size_token));
}

test "packet decl: header fields and body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src =
        \\protocol P { endian: big, }
        \\states { Play = 0, }
        \\packet Move : Play[0x07] -> Server { entityId: u32, pos: Vec3, }
    ;
    const ast = try testParse(arena.allocator(), src);

    const pkt = ast.nodes[ast.file.decls[0]].packet;
    try testing.expectEqualStrings("Move", ast.tokenText(pkt.name));
    try testing.expectEqualStrings("Play", ast.tokenText(pkt.state));
    try testing.expectEqualStrings("0x07", ast.tokenText(pkt.id));
    try testing.expectEqualStrings("Server", ast.tokenText(pkt.direction));
    try testing.expectEqual(@as(usize, 2), pkt.fields.len);
    try testing.expectEqualStrings("entityId", ast.tokenText(pkt.fields[0].name));
    try testing.expectEqualStrings("u32", ast.tokenText(pkt.fields[0].type.named));
    try testing.expectEqualStrings("pos", ast.tokenText(pkt.fields[1].name));
}

test "packet decl: decimal packet id" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "protocol P { endian: big, } states { S = 0, } packet Ping : S[7] -> Client { }";
    const ast = try testParse(arena.allocator(), src);

    const pkt = ast.nodes[ast.file.decls[0]].packet;
    try testing.expectEqualStrings("7", ast.tokenText(pkt.id));
    try testing.expectEqualStrings("Client", ast.tokenText(pkt.direction));
    try testing.expectEqual(@as(usize, 0), pkt.fields.len);
}

test "multiple decls: enum + struct + packet" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src =
        \\protocol P { endian: big, }
        \\states { S = 0, }
        \\enum Dir : u8 { N = 0, }
        \\struct Pt { x: f32, }
        \\packet Go : S[0x01] -> Server { }
    ;
    const ast = try testParse(arena.allocator(), src);

    try testing.expectEqual(@as(usize, 3), ast.file.decls.len);
    try testing.expectEqual(@as(usize, 3), ast.nodes.len);
    try testing.expectEqual(std.meta.Tag(Node).@"enum", std.meta.activeTag(ast.nodes[0]));
    try testing.expectEqual(std.meta.Tag(Node).@"struct", std.meta.activeTag(ast.nodes[1]));
    try testing.expectEqual(std.meta.Tag(Node).packet, std.meta.activeTag(ast.nodes[2]));
}

test "error: file starts with states instead of protocol" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "states { S = 0, } protocol P { endian: big, }";
    try testing.expectError(error.UnexpectedToken, testParse(arena.allocator(), src));
}

test "error: missing states block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "protocol P { endian: big, } enum E : u8 { }";
    try testing.expectError(error.UnexpectedToken, testParse(arena.allocator(), src));
}

test "error: unknown top-level token after states" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // An identifier at the top-level is not a valid decl opener.
    const src = "protocol P { endian: big, } states { S = 0, } foo";
    try testing.expectError(error.UnexpectedToken, testParse(arena.allocator(), src));
}

test "error: missing comma after field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src = "protocol P { endian: big, } states { S = 0, } struct V { x: f64 }";
    try testing.expectError(error.UnexpectedToken, testParse(arena.allocator(), src));
}
