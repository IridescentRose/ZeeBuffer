const std = @import("std");
const util = @import("util.zig");

// All valid schema tokens
pub const TokenKind = enum(u16) {
    EOF = 0,
    Colon = 1,
    LSquirly = 2,
    RSquirly = 3,
    Comma = 4,
    LParen = 5,
    RParen = 6,
    Ident = 7,
    Equal = 8,
    KWEnum = 9,
    KWEvent = 10,
    KWCompressed = 11,
    KWEncrypted = 12,
    KWPacket = 13,
    KWEndian = 14,
};

// Pairs for map
const PairKWStr = struct {
    kind: TokenKind,
    str: []const u8,
};

// All valid schema keywords
const KWStrs = [_]PairKWStr{
    .{ .kind = .KWEnum, .str = "Enum" },
    .{ .kind = .KWEvent, .str = "Event" },
    .{ .kind = .KWCompressed, .str = "Compressed" },
    .{ .kind = .KWEncrypted, .str = "Encrypted" },
    .{ .kind = .KWPacket, .str = "@packet" },
    .{ .kind = .KWEndian, .str = "@endian" },
};

// A token in the schema
pub const Token = struct {
    kind: TokenKind,
    start: u16,
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

            ':' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.Colon,
                    .start = self.curr_index,
                });
            },

            '{' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.LSquirly,
                    .start = self.curr_index,
                });
            },

            '}' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.RSquirly,
                    .start = self.curr_index,
                });
            },

            ',' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.Comma,
                    .start = self.curr_index,
                });
            },

            '(' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.LParen,
                    .start = self.curr_index,
                });
            },

            ')' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.RParen,
                    .start = self.curr_index,
                });
            },

            '=' => {
                try self.default_ident(&tokenArray);
                try tokenArray.append(Token{
                    .kind = TokenKind.Equal,
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
