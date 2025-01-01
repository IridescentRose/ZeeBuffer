const std = @import("std");
const assert = std.debug.assert;

const util = @import("../util.zig");

const Self = @This();

pub const TokenKind = enum(u8) {
    EOF = 0,
    LSquirly = 1,
    RSquirly = 2,
    LParen = 3,
    RParen = 4,
    Colon = 5,
    Comma = 6,
    Ident = 7,
    KWEnum = 8,
    KWEvent = 9,
    KWEndian = 10,
    KWState = 11,
    KWClient = 12,
    KWServer = 13,
    KWBoth = 14,
    KWVarArray = 15,
    KWFixedArray = 16,
};

pub const Token = packed struct(u32) {
    kind: TokenKind,
    len: u8 = 1,
    start: u16,
};

const PairSymStr = struct {
    kind: TokenKind,
    char: u8,
};

// All valid schema symbols
const SymStrs = [_]PairSymStr{
    .{ .kind = .Colon, .char = ':' },
    .{ .kind = .LParen, .char = '(' },
    .{ .kind = .RParen, .char = ')' },
    .{ .kind = .LSquirly, .char = '{' },
    .{ .kind = .RSquirly, .char = '}' },
};

const PairKWStr = struct {
    kind: TokenKind,
    str: []const u8,
};

const KWStrs = [_]PairKWStr{
    .{ .kind = .KWEnum, .str = "Enum" },
    .{ .kind = .KWEvent, .str = "Event" },
    .{ .kind = .KWEndian, .str = "@endian" },
    .{ .kind = .KWState, .str = "@state" },
    .{ .kind = .KWClient, .str = "Client" },
    .{ .kind = .KWServer, .str = "Server" },
    .{ .kind = .KWBoth, .str = "Both" },
    .{ .kind = .KWVarArray, .str = "VarArray" },
    .{ .kind = .KWFixedArray, .str = "Array" },
};

curr_idx: u16 = 0,
ident_len: u8 = 0,
in_ident: bool = false,
source: []const u8,

pub fn init(source: []const u8) Self {
    assert(source.len < std.math.maxInt(u16));

    return .{
        .source = source,
    };
}

pub fn tokenize(self: *Self) ![]Token {
    var tokenArray = std.ArrayList(Token).init(util.allocator());

    while (self.curr_idx < self.source.len) : (self.curr_idx += 1) {
        switch (self.source[self.curr_idx]) {
            // New lines, spaces, tabs, and carriage returns
            ' ', '\n', '\t', '\r' => {
                try self.default_ident(&tokenArray);
            },

            // Comments
            '#' => {
                try self.default_ident(&tokenArray);
                while (self.curr_idx < self.source.len) : (self.curr_idx += 1) {
                    if (self.source[self.curr_idx] == '\n') {
                        break;
                    }
                }
            },

            // Symbols
            ':', '{', '}', ',', '(', ')' => |c| {
                try self.default_ident(&tokenArray);

                if (c == ',') { // Skip commas
                    continue;
                }

                try tokenArray.append(Token{
                    .kind = inline for (SymStrs) |pair| {
                        if (c == pair.char) {
                            break pair.kind;
                        }
                    } else unreachable,
                    .start = self.curr_idx,
                });
            },

            // Identifiers
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
        .start = self.curr_idx,
        .len = 0,
    });

    // Filter identifiers to keywords
    for (tokenArray.items) |*token| {
        if (token.kind == TokenKind.Ident) {
            for (KWStrs) |kwStr| {
                if (std.mem.eql(u8, self.source[token.start .. token.start + token.len], kwStr.str)) {
                    token.kind = kwStr.kind;
                    break;
                }
            }
        }
    }

    return try tokenArray.toOwnedSlice();
}

// Check if we are in an identifier and if so, add it to the token array
fn default_ident(self: *Self, tokenArray: *std.ArrayList(Token)) !void {
    if (self.in_ident and self.ident_len > 0) {
        try tokenArray.append(.{
            .kind = TokenKind.Ident,
            .start = self.curr_idx - self.ident_len,
            .len = self.ident_len,
        });

        self.in_ident = false;
        self.ident_len = 0;
    }
}
