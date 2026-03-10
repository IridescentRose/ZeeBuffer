const std = @import("std");
const Io = std.Io;

pub const TokenKind = enum(u8) {
    // Single-character tokens — identity-mapped to their ASCII values.
    comma = ',', // 44
    colon = ':', // 58
    semicolon = ';', // 59
    equals = '=', // 61
    l_bracket = '[', // 91
    r_bracket = ']', // 93
    l_brace = '{', // 123
    r_brace = '}', // 125

    // Multi-character tokens — assigned above the ASCII range.
    arrow = 128, // ->
    identifier = 129,
    int_literal = 130, // hex, dec, or oct

    eof = 132,

    // Keywords — must come last.
    kw_protocol = 133,
    kw_states = 134,
    kw_enum = 135,
    kw_struct = 136,
    kw_packet = 137,
};

pub const Token = packed struct(u32) {
    kind: TokenKind,
    len: u8,
    start: u16,
};

const KeywordMap = std.StaticStringMap(TokenKind);
const KeywordPairs = .{
    .{ "protocol", TokenKind.kw_protocol },
    .{ "states", TokenKind.kw_states },
    .{ "enum", TokenKind.kw_enum },
    .{ "struct", TokenKind.kw_struct },
    .{ "packet", TokenKind.kw_packet },
};

fn isDecDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHexDigit(c: u8) bool {
    return isDecDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or isDecDigit(c) or c == '_';
}

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var tokens = try std.ArrayList(Token).initCapacity(allocator, source.len / 4);
    errdefer tokens.deinit(allocator);

    var i: u16 = 0;
    if (source.len >= 3 and source[0] == 0xEF and source[1] == 0xBB and source[2] == 0xBF) {
        i = 3;
    }

    const kmap = KeywordMap.initComptime(KeywordPairs);

    while (true) : (i += 1) {
        if (i >= source.len) {
            @branchHint(.unlikely);
            break;
        }

        @prefetch(source.ptr + i, .{});

        switch (source[i]) {
            // Skip whitespace.
            ' ', '\t', '\r', '\n' => {},

            // Skip comments until end of line.
            '#' => {
                while (i + 1 < source.len and source[i + 1] != '\n') : (i += 1) {}
            },

            // Single-character tokens — @enumFromInt is safe here because all
            // chars in this set are valid TokenKind tags via identity mapping.
            ',', ':', ';', '=', '[', ']', '{', '}' => {
                try tokens.append(allocator, .{
                    .kind = @enumFromInt(source[i]),
                    .start = i,
                    .len = 1,
                });
            },

            // Arrow: the only two-character punctuation token.
            '-' => {
                if (i + 1 >= source.len or source[i + 1] != '>') {
                    return error.UnexpectedCharacter;
                }
                try tokens.append(allocator, .{ .kind = .arrow, .start = i, .len = 2 });
                i += 1;
            },

            // Integer literals — decimal or hex (0x...).
            // No value parsing; the raw source slice is left to the parser.
            '0'...'9' => {
                const start = i;
                if (source[i] == '0' and i + 1 < source.len and source[i + 1] == 'x') {
                    // Hex: consume '0x' then all following hex digits.
                    i += 2;
                    while (i < source.len and isHexDigit(source[i])) : (i += 1) {}
                    // Step back so the loop's i += 1 lands on the next character.
                    i -= 1;
                } else {
                    // Decimal: consume all following decimal digits.
                    while (i + 1 < source.len and isDecDigit(source[i + 1])) : (i += 1) {}
                }
                const len: u16 = i - start + 1;
                if (len > std.math.maxInt(u8)) return error.TokenTooLong;
                try tokens.append(allocator, .{
                    .kind = .int_literal,
                    .start = start,
                    .len = @intCast(len),
                });
            },

            // Identifiers and keywords.
            'a'...'z', 'A'...'Z', '_' => {
                const start = i;
                while (i + 1 < source.len and isIdentChar(source[i + 1])) : (i += 1) {}
                const len: u16 = i - start + 1;
                if (len > std.math.maxInt(u8)) return error.IdentifierTooLong;
                const word = source[start .. start + len];
                const kind = kmap.get(word) orelse .identifier;
                try tokens.append(allocator, .{
                    .kind = kind,
                    .start = start,
                    .len = @intCast(len),
                });
            },

            else => return error.UnexpectedCharacter,
        }
    }

    tokens.shrinkAndFree(allocator, tokens.items.len);

    return tokens.toOwnedSlice(allocator);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "empty source produces no tokens" {
    const toks = try tokenize(std.testing.allocator, "");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 0), toks.len);
}

test "single-character tokens" {
    const toks = try tokenize(std.testing.allocator, ", : ; = [ ] { }");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 8), toks.len);
    try std.testing.expectEqual(TokenKind.comma, toks[0].kind);
    try std.testing.expectEqual(TokenKind.colon, toks[1].kind);
    try std.testing.expectEqual(TokenKind.semicolon, toks[2].kind);
    try std.testing.expectEqual(TokenKind.equals, toks[3].kind);
    try std.testing.expectEqual(TokenKind.l_bracket, toks[4].kind);
    try std.testing.expectEqual(TokenKind.r_bracket, toks[5].kind);
    try std.testing.expectEqual(TokenKind.l_brace, toks[6].kind);
    try std.testing.expectEqual(TokenKind.r_brace, toks[7].kind);
}

test "arrow token" {
    const toks = try tokenize(std.testing.allocator, "->");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.arrow, toks[0].kind);
    try std.testing.expectEqual(@as(u8, 2), toks[0].len);
    try std.testing.expectEqual(@as(u16, 0), toks[0].start);
}

test "bare dash is an error" {
    try std.testing.expectError(error.UnexpectedCharacter, tokenize(std.testing.allocator, "-"));
}

test "comment is skipped" {
    const toks = try tokenize(std.testing.allocator, "# a comment\nfoo");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.identifier, toks[0].kind);
}

test "comment with no trailing newline is skipped" {
    const toks = try tokenize(std.testing.allocator, "# no newline at eof");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 0), toks.len);
}

test "tokens before and after comment" {
    const toks = try tokenize(std.testing.allocator, "a # comment\n b");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 2), toks.len);
    try std.testing.expectEqual(TokenKind.identifier, toks[0].kind);
    try std.testing.expectEqual(TokenKind.identifier, toks[1].kind);
}

test "identifier start and length" {
    const src = "myField";
    const toks = try tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.identifier, toks[0].kind);
    try std.testing.expectEqual(@as(u16, 0), toks[0].start);
    try std.testing.expectEqual(@as(u8, 7), toks[0].len);
}

test "identifier with leading underscore and digits" {
    const toks = try tokenize(std.testing.allocator, "_field2");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.identifier, toks[0].kind);
    try std.testing.expectEqual(@as(u8, 7), toks[0].len);
}

test "all keywords resolve correctly" {
    const cases = .{
        .{ "protocol", TokenKind.kw_protocol },
        .{ "states", TokenKind.kw_states },
        .{ "enum", TokenKind.kw_enum },
        .{ "struct", TokenKind.kw_struct },
        .{ "packet", TokenKind.kw_packet },
    };
    inline for (cases) |c| {
        const toks = try tokenize(std.testing.allocator, c[0]);
        defer std.testing.allocator.free(toks);
        try std.testing.expectEqual(@as(usize, 1), toks.len);
        try std.testing.expectEqual(c[1], toks[0].kind);
    }
}

test "keyword prefix is an identifier" {
    // "protocols" starts with "protocol" but is not a keyword.
    const toks = try tokenize(std.testing.allocator, "protocols");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.identifier, toks[0].kind);
}

test "decimal integer literal" {
    const toks = try tokenize(std.testing.allocator, "255");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.int_literal, toks[0].kind);
    try std.testing.expectEqual(@as(u8, 3), toks[0].len);
}

test "hex integer literal" {
    const toks = try tokenize(std.testing.allocator, "0x1F");
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.int_literal, toks[0].kind);
    try std.testing.expectEqual(@as(u8, 4), toks[0].len);
}

test "identifier too long returns error" {
    // 256 'a's exceeds the u8 length limit of 255.
    var buf: [256]u8 = undefined;
    @memset(&buf, 'a');
    try std.testing.expectError(error.IdentifierTooLong, tokenize(std.testing.allocator, &buf));
}

test "identifier at exactly max length is accepted" {
    var buf: [255]u8 = undefined;
    @memset(&buf, 'a');
    const toks = try tokenize(std.testing.allocator, &buf);
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(@as(u8, 255), toks[0].len);
}

test "unknown character returns error" {
    try std.testing.expectError(error.UnexpectedCharacter, tokenize(std.testing.allocator, "@"));
}

test "utf-8 bom is skipped" {
    const src = "\xEF\xBB\xBFfoo";
    const toks = try tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(toks);
    try std.testing.expectEqual(@as(usize, 1), toks.len);
    try std.testing.expectEqual(TokenKind.identifier, toks[0].kind);
    // start should be 3, past the 3-byte BOM.
    try std.testing.expectEqual(@as(u16, 3), toks[0].start);
}

test "realistic packet declaration" {
    const src = "packet Foo : Play[0x07] -> Server { id: u32, }";
    const toks = try tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(toks);
    // Expected sequence:
    // kw_packet  ident  colon  ident  l_bracket  int_literal  r_bracket
    // arrow  ident  l_brace  ident  colon  ident  comma  r_brace
    try std.testing.expectEqual(@as(usize, 15), toks.len);
    try std.testing.expectEqual(TokenKind.kw_packet, toks[0].kind);
    try std.testing.expectEqual(TokenKind.identifier, toks[1].kind);
    try std.testing.expectEqual(TokenKind.colon, toks[2].kind);
    try std.testing.expectEqual(TokenKind.identifier, toks[3].kind);
    try std.testing.expectEqual(TokenKind.l_bracket, toks[4].kind);
    try std.testing.expectEqual(TokenKind.int_literal, toks[5].kind);
    try std.testing.expectEqual(TokenKind.r_bracket, toks[6].kind);
    try std.testing.expectEqual(TokenKind.arrow, toks[7].kind);
    try std.testing.expectEqual(TokenKind.identifier, toks[8].kind);
    try std.testing.expectEqual(TokenKind.l_brace, toks[9].kind);
    try std.testing.expectEqual(TokenKind.identifier, toks[10].kind);
    try std.testing.expectEqual(TokenKind.colon, toks[11].kind);
    try std.testing.expectEqual(TokenKind.identifier, toks[12].kind);
    try std.testing.expectEqual(TokenKind.comma, toks[13].kind);
    try std.testing.expectEqual(TokenKind.r_brace, toks[14].kind);
}
