const std = @import("std");
const util = @import("util.zig");
const SourceObject = @import("SourceObject.zig");
const Tokenizer = @import("Tokenizer.zig");
const AST = @import("AST.zig");

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

fn parse_fields(self: *Self, tokens: []const Tokenizer.Token) ![]AST.Field {
    var fields = std.ArrayList(AST.Field).init(util.allocator());

    // Consume opening squirly brace
    self.curr_token += 1;

    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        // Check if we are at the end of the fields
        if (tokens[self.curr_token].kind == .RSquirly) {
            break;
        }

        // Parse field
        try self.expect(tokens, .Ident);

        // Grab field name
        const name: AST.Index = @intCast(self.curr_token);

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

        // Check if the field is an event
        if (tokens[self.curr_token + 1].kind == .KWEvent) {
            try self.expect_next(tokens, .KWEvent);
            const kind: AST.Index = @intCast(self.curr_token);

            // Consume opening paren
            try self.expect_next(tokens, .LParen);
            // Consume ident
            try self.expect_next(tokens, .Ident);
            // Consume closing paren
            try self.expect_next(tokens, .RParen);

            try fields.append(.{ .name = name, .kind = kind, .len_kind = 3 });
            continue;
        }

        try self.expect_next(tokens, .Ident);
        const kind: AST.Index = @intCast(self.curr_token);

        try fields.append(.{ .name = name, .kind = kind });
    }

    return try fields.toOwnedSlice();
}

fn parse_attributes(self: *Self, tokens: []const Tokenizer.Token) ![]AST.Attribute {
    var attributes = std.ArrayList(AST.Attribute).init(util.allocator());

    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        const token = tokens[self.curr_token];

        // Check if we are at the end of the attributes
        if (token.kind == .LSquirly) {
            break;
        }

        // Parse attribute
        const kind: AST.AttributeType = switch (token.kind) {
            .KWEnum => .Enum,
            .KWIn => .InEvent,
            .KWOut => .OutEvent,
            .KWInOut => .InOutEvent,
            .KWCompressed => .Compressed,
            .KWEncrypted => .Encrypted,
            .KWStateEvent => .State,
            else => {
                const location = self.source.get_source_location(token);
                const source = self.source.get_source_string(token);

                std.debug.print("Expected attribute token, but got {s}!\n", .{self.source.token_text(token)});
                std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                std.debug.print("{s}\n", .{source});

                return error.SyntaxUnexpectedToken;
            },
        };

        // Consume attribute value
        try self.expect_next(tokens, .LParen);
        try self.expect_next(tokens, .Ident);

        // Grab index
        const index: AST.Index = @intCast(self.curr_token);

        // Consume closing parenthesis
        try self.expect_next(tokens, .RParen);

        // Add attribute
        try attributes.append(.{ .type = kind, .value = index });
    }

    return try attributes.toOwnedSlice();
}

pub fn parse(self: *Self) !AST {
    std.debug.print("Parsing protocol...\n", .{});

    // AST to return
    var entries = std.ArrayList(AST.Entry).init(util.allocator());
    var endian: AST.Endian = .Little;
    var direction: AST.Direction = .In;

    const tokens = self.source.tokens;
    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        const token = tokens[self.curr_token];

        switch (token.kind) {
            .KWEndian => {
                try self.expect_next(tokens, .Ident);
                const ident = tokens[self.curr_token];

                // zig fmt: off
                endian =
                    if (std.mem.eql(u8, self.source.token_text(ident), "little"))
                        .Little
                    else if (std.mem.eql(u8, self.source.token_text(ident), "big"))
                        .Big
                    else blk: {
                        const source = self.source.get_source_string(ident);
                        const location = self.source.get_source_location(ident);

                        std.debug.print("Expected 'little' or 'big' after '@endian', but got {s}!\n", .{self.source.token_text(ident)});
                        std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                        std.debug.print("{s}\n", .{source});
                        std.debug.print("Endianness is set to 'little' by default\n", .{});
                        
                        break :blk .Little;
                    };
                // zig fmt: on
            },

            .KWDirection => {
                try self.expect_next(tokens, .Ident);
                const ident = tokens[self.curr_token];

                // zig fmt: off
                direction =
                    if (std.mem.eql(u8, self.source.token_text(ident), "in"))
                        .In
                    else if (std.mem.eql(u8, self.source.token_text(ident), "out"))
                        .Out
                    else blk: {
                        const location = self.source.get_source_location(ident);
                        const source = self.source.get_source_string(ident);
                        
                        std.debug.print("Expected 'in' or 'out' after '@direction', but got {s}!\n", .{self.source.token_text(ident)});
                        std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                        std.debug.print("{s}\n", .{source});
                        std.debug.print("Direction is set to 'in' by default\n", .{});
                        
                        break :blk .In;
                    };
                // zig fmt: on
            },

            .KWState, .KWPacket, .Ident => {
                var entry: AST.Entry = .{
                    .name = @intCast(self.curr_token),
                    .fields = &[_]AST.Field{},
                };

                // zig fmt: off
                // Set special
                entry.special =
                    if (token.kind == .KWState)
                        .State
                    else if (token.kind == .KWPacket)
                        .Packet
                    else
                        entry.special;
                // zig fmt: on

                // Verify that there is a colon or opening squiggly brace
                if (self.curr_token + 1 >= tokens.len) {
                    const location = self.source.get_source_location(token);
                    const source = self.source.get_source_string(token);

                    std.debug.print("Expected ':' or '{{' after declaration, but got EOF\n", .{});
                    std.debug.print("At line {}, column {}\n", .{ location.line, location.column });
                    std.debug.print("{s}\n", .{source});

                    return error.SyntaxUnexpectedToken;
                }

                // Peek next token without consuming -- we need to know if there are attributes
                self.curr_token += 1;
                const next_token = tokens[self.curr_token];

                if (token.kind == .KWState and next_token.kind == .Colon) { // States cannot have attributes
                    std.debug.print("States cannot have attributes!\n", .{});
                    return error.SyntaxStateAttributes;
                } else if (next_token.kind == .Colon) { // Parse attributes if any are present
                    // Parse attributes
                    self.curr_token += 1;
                    entry.attributes = try self.parse_attributes(tokens);
                }

                // Check if we are at the start of the fields
                try self.expect(tokens, .LSquirly);

                // Parse fields
                entry.fields = try self.parse_fields(tokens);

                // Verify that we're on the closing squirly brace
                try self.expect(tokens, .RSquirly);

                try entries.append(entry);
            },

            .EOF => break,
            else => @panic("Compiler errror: Unexpected token in parser!\nPlease report this bug here: https://github.com/IridescentRose/ZeeBuffer/issues"),
        }
    }

    return .{
        .endian = endian,
        .direction = direction,
        .entries = try entries.toOwnedSlice(),
    };
}
