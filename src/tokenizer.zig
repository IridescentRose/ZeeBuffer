const std = @import("std");
const util = @import("util.zig");

// All valid schema tokens
pub const TokenKind = enum(u16) {
    EOF = 0,
    LSquirly = 1,
    RSquirly = 2,
    LParen = 3,
    RParen = 4,
    Colon = 5,
    Comma = 6,
    Ident = 7,
    KWIn = 8,
    KWInOut = 9,
    KWOut = 10,
    KWEnum = 11,
    KWEvent = 12,
    KWCompressed = 13,
    KWEncrypted = 14,
    KWPacket = 15,
    KWEndian = 16,
    KWDirection = 17,
    KWState = 18,
    KWStateEvent = 19,
};

// Pairs for symbols
const PairSymStr = struct {
    kind: TokenKind,
    char: u8,
};

// Pairs for map
const PairKWStr = struct {
    kind: TokenKind,
    str: []const u8,
};

// All valid schema keywords
const KWStrs = [_]PairKWStr{
    .{ .kind = .KWIn, .str = "In" },
    .{ .kind = .KWInOut, .str = "InOut" },
    .{ .kind = .KWOut, .str = "Out" },
    .{ .kind = .KWEnum, .str = "Enum" },
    .{ .kind = .KWEvent, .str = "Event" },
    .{ .kind = .KWCompressed, .str = "Compressed" },
    .{ .kind = .KWEncrypted, .str = "Encrypted" },
    .{ .kind = .KWStateEvent, .str = "State" },
    .{ .kind = .KWPacket, .str = "@packet" },
    .{ .kind = .KWEndian, .str = "@endian" },
    .{ .kind = .KWDirection, .str = "@direction" },
    .{ .kind = .KWState, .str = "@state" },
};

// All valid schema symbols
const SymStrs = [_]PairSymStr{
    .{ .kind = .Colon, .char = ':' },
    .{ .kind = .LParen, .char = '(' },
    .{ .kind = .RParen, .char = ')' },
    .{ .kind = .LSquirly, .char = '{' },
    .{ .kind = .RSquirly, .char = '}' },
};

// A token in the schema
pub const Token = struct {
    kind: TokenKind,
    start: u16,
    len: u16 = 1,
};

const Self = @This();

curr_index: u16 = 0,
ident_len: u16 = 0,
in_ident: bool = false,
source: []const u8,

// Create a new tokenizer
pub fn create(source: []const u8) !Self {
    if (source.len >= std.math.maxInt(u16))
        return error.SourceTooBig;

    return Self{
        .source = source,
    };
}

// Check if we are in an identifier and if so, add it to the token array
fn default_ident(self: *Self, tokenArray: *std.ArrayList(Token)) !void {
    if (self.in_ident and self.ident_len > 0) {
        const token = Token{
            .kind = TokenKind.Ident,
            .start = self.curr_index - self.ident_len,
            .len = self.ident_len,
        };
        try tokenArray.append(token);

        self.in_ident = false;
        self.ident_len = 0;
    }
}

pub fn tokenize(self: *Self) ![]Token {
    const allocator = util.allocator();
    var tokenArray = std.ArrayList(Token).init(allocator);

    while (self.curr_index < self.source.len) : (self.curr_index += 1) {
        const c = self.source[self.curr_index];

        switch (c) {
            ' ', '\n', '\t', '\r' => {
                try self.default_ident(&tokenArray);
            },

            '#' => {
                try self.default_ident(&tokenArray);
                while (self.curr_index < self.source.len) : (self.curr_index += 1) {
                    if (self.source[self.curr_index] == '\n') {
                        break;
                    }
                }
            },

            ':', '{', '}', ',', '(', ')' => {
                try self.default_ident(&tokenArray);

                if (c == ',') {
                    break;
                }

                try tokenArray.append(Token{
                    .kind = inline for (SymStrs) |pair| {
                        if (c == pair.char) {
                            break pair.kind;
                        }
                    } else TokenKind.EOF,
                    .start = self.curr_index,
                });
            },

            else => {
                self.in_ident = true;
                self.ident_len += 1;
            },
        }
    }
    // Add the last identifier & EOF
    try self.default_ident(&tokenArray);
    try tokenArray.append(Token{
        .kind = TokenKind.EOF,
        .start = self.curr_index,
    });

    // Filter identifiers to keywords
    for (tokenArray.items) |*token| {
        if (token.kind == TokenKind.Ident) {
            for (KWStrs) |kwStr| {
                if (token.start + kwStr.str.len > self.source.len) {
                    continue;
                }

                if (std.mem.eql(u8, self.source[token.start .. token.start + kwStr.str.len], kwStr.str)) {
                    token.kind = kwStr.kind;
                    break;
                }
            }
        }
    }

    // Return the token array
    return try tokenArray.toOwnedSlice();
}