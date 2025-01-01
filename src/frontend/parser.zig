const std = @import("std");
const assert = std.debug.assert;

const util = @import("../util.zig");

const AST = @import("../AST.zig");
const SourceObject = @import("../SourceObject.zig");

const Tokenizer = @import("tokenizer.zig");

const Self = @This();

source: SourceObject,
curr_token: usize,

pub fn init(source: SourceObject) Self {
    return Self{
        .source = source,
        .curr_token = 0,
    };
}

fn expect_next(self: *Self, tokens: []const Tokenizer.Token, kind: Tokenizer.TokenKind) !void {
    if (self.curr_token + 1 >= tokens.len) {
        const token = tokens[self.curr_token];

        const location = self.source.get_source_location(token);
        const source = self.source.get_source_string(token);

        std.debug.print("Expected token of type {s}, but got EOF\n", .{@tagName(kind)});
        std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
        std.debug.print("{s}\n", .{source});

        return error.SyntaxUnexpectedToken;
    }

    self.curr_token += 1;

    try expect(self, tokens, kind);
}

fn expect(self: *Self, tokens: []const Tokenizer.Token, kind: Tokenizer.TokenKind) !void {
    const token = tokens[self.curr_token];

    if (token.kind != kind) {
        const location = self.source.get_source_location(token);
        const source = self.source.get_source_string(token);

        std.debug.print("Expected token of type {s}, but got {s}\n", .{ @tagName(kind), @tagName(token.kind) });
        std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
        std.debug.print("{s}\n", .{source});

        return error.SyntaxUnexpectedToken;
    }
}

pub fn parse(self: *Self) !AST {
    var entries = std.ArrayList(AST.Entry).init(util.allocator());
    var endian = AST.Endian.little;

    const tokens = self.source.tokens;
    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        const token = tokens[self.curr_token];

        switch (token.kind) {
            .KWEndian => {
                try self.expect_next(tokens, .Ident);
                const ident = tokens[self.curr_token];

                endian =
                    if (std.mem.eql(u8, self.source.get_token_text(ident), "little"))
                    .little
                else if (std.mem.eql(u8, self.source.get_token_text(ident), "big"))
                    .big
                else blk: {
                    const source = self.source.get_source_string(ident);
                    const location = self.source.get_source_location(ident);

                    std.debug.print("Expected 'little' or 'big' after '@endian', but got {s}!\n", .{self.source.get_token_text(ident)});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});
                    std.debug.print("Endianness is set to 'little' by default\n", .{});

                    break :blk .little;
                };
            },

            .KWState, .Ident => {
                var entry = AST.Entry{
                    .name = @intCast(self.curr_token),
                    .is_state = token.kind == .KWState,
                    .fields = undefined,
                };

                // Verify that there is a colon or opening squiggly brace
                if (self.curr_token + 1 >= tokens.len) {
                    const location = self.source.get_source_location(token);
                    const source = self.source.get_source_string(token);

                    std.debug.print("Expected ':' or '{{' after declaration, but got EOF\n", .{});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});

                    return error.SyntaxUnexpectedToken;
                }

                self.curr_token += 1;
                const next_token = tokens[self.curr_token];

                if (token.kind == .KWState and next_token.kind == .Colon) { // States cannot have attributes
                    const location = self.source.get_source_location(token);
                    const source = self.source.get_source_string(token);

                    std.debug.print("States cannot have attributes!\n", .{});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});

                    return error.SyntaxStateAttributes;
                } else if (next_token.kind == .Colon) { // Parse attributes if any are present
                    // Parse attributes
                    self.curr_token += 1;
                    entry.attribute = try self.parse_attribute(tokens);
                }

                try self.expect(tokens, .LSquirly);
                entry.fields = try self.parse_fields(tokens);
                try self.expect(tokens, .RSquirly);

                try entries.append(entry);
            },

            .EOF => break,
            else => unreachable,
        }
    }

    return AST{
        .endian = endian,
        .entries = try entries.toOwnedSlice(),
    };
}

fn parse_attribute(self: *Self, tokens: []const Tokenizer.Token) !AST.Attribute {
    var token = tokens[self.curr_token];
    var values = std.ArrayList(AST.Index).init(util.allocator());

    const kind: AST.AttributeKind = if (token.kind == .KWEnum) .Enum else if (token.kind == .KWEvent) .Event else unreachable;

    try self.expect_next(tokens, .LParen);
    self.curr_token += 1;

    while (self.curr_token < self.source.tokens.len) : (self.curr_token += 1) {
        token = self.source.tokens[self.curr_token];
        if (token.kind == .RParen or token.kind == .EOF)
            break;

        try values.append(@intCast(self.curr_token));
    }

    try self.expect(tokens, .RParen);
    try self.expect_next(tokens, .LSquirly);

    return AST.Attribute{
        .kind = kind,
        .values = try values.toOwnedSlice(),
    };
}

fn parse_fields(self: *Self, tokens: []const Tokenizer.Token) ![]AST.Field {
    var fields = std.ArrayList(AST.Field).init(util.allocator());

    // Consume opening brace
    self.curr_token += 1;

    while (self.curr_token < self.source.tokens.len) : (self.curr_token += 1) {
        var token = tokens[self.curr_token];
        if (token.kind == .EOF or token.kind == .RSquirly)
            break;

        // This should be the name field
        try self.expect(tokens, .Ident);

        const name: AST.Index = @intCast(self.curr_token);
        var values = std.ArrayList(AST.Index).init(util.allocator());

        // Consume colon
        try self.expect_next(tokens, .Colon);

        // Check if we are at the end of the tokens
        if (self.curr_token + 1 >= tokens.len) {
            const source = self.source.get_source_string(tokens[self.curr_token]);
            const location = self.source.get_source_location(tokens[self.curr_token]);

            std.debug.print("Expected field type, but got EOF\n", .{});
            std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
            std.debug.print("{s}\n", .{source});

            return error.SyntaxUnexpectedToken;
        }

        self.curr_token += 1;
        token = tokens[self.curr_token];

        if (token.kind == .Ident) {
            try values.append(@intCast(self.curr_token));
        } else if (token.kind == .KWVarArray or token.kind == .KWFixedArray) {
            try values.append(@intCast(self.curr_token));
            try self.expect_next(tokens, .LParen);

            try self.expect_next(tokens, .Ident);
            try values.append(@intCast(self.curr_token));

            try self.expect_next(tokens, .Ident);
            try values.append(@intCast(self.curr_token));

            try self.expect_next(tokens, .RParen);
        } else {
            try self.expect(tokens, .Ident);
        }

        try fields.append(.{
            .name = name,
            .values = try values.toOwnedSlice(),
        });
    }

    return try fields.toOwnedSlice();
}
