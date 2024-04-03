const std = @import("std");
const util = @import("util.zig");
const Tokenizer = @import("tokenizer.zig");

pub const Index = u16;

pub const AttributeType = enum(u16) {
    Enum,
    InEvent,
    OutEvent,
    InOutEvent,
    Compressed,
    Encrypted,
    State,
};

pub const Attribute = struct {
    type: AttributeType,
    value: Index,
};

pub const Field = struct {
    name: Index,
    kind: Index,
    len_kind: u32 = 0,
};

pub const Special = enum {
    None,
    State,
    Packet,
};

pub const Entry = struct {
    name: Index,
    special: Special = .None,
    attributes: ?[]Attribute = null,
    fields: []Field,
};

pub const Endian = enum {
    Little,
    Big,
};

pub const Direction = enum {
    In,
    Out,
};

pub const Protocol = struct {
    endian: Endian = .Little,
    direction: Direction = .In,
    entries: std.ArrayList(Entry),
};

const Self = @This();
source: []const u8 = undefined,
curr_token: usize = 0,

const Location = struct {
    line: u32,
    column: u32,
};

fn get_source_location(self: *Self, token: Tokenizer.Token) Location {
    var line: u32 = 1;
    var column: u32 = 1;

    var i: usize = 0;
    while (i < token.start) : (i += 1) {
        if (self.source[i] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

fn get_source_string(self: *Self, token: Tokenizer.Token) []const u8 {
    const WINDOW_SIZE = 64;
    const start = if (token.start - WINDOW_SIZE < 0) 0 else token.start - WINDOW_SIZE;
    const end = if (token.start + token.len + WINDOW_SIZE > self.source.len) self.source.len else token.start + token.len + WINDOW_SIZE;

    const startNewLine = token.start - (std.mem.indexOf(u8, self.source[start..token.start], "\n") orelse 0);
    const endNewLine = (std.mem.indexOf(u8, self.source[token.start..end], "\n") orelse 0) + token.start;

    return self.source[startNewLine..endNewLine];
}

fn print_source(self: *Self, token: Tokenizer.Token) void {
    const location = self.get_source_location(token);
    const source = self.get_source_string(token);

    std.debug.print("{}:{}:\n", .{ location.line, location.column });
    std.debug.print("{s}\n", .{source});
}

fn expect_next(self: *Self, tokens: []Tokenizer.Token, kind: Tokenizer.TokenKind) !void {
    if (self.curr_token + 1 >= tokens.len) {
        std.debug.print("Expected token of type {s}, but got EOF\n", .{@tagName(kind)});
        return error.UnexpectedToken;
    }

    const token = tokens[self.curr_token + 1];

    if (token.kind != kind) {
        const location = self.get_source_location(token);
        const source = self.get_source_string(token);

        std.debug.print("{}:{}: Expected token of type {s}, but got {s}\n", .{ location.line, location.column, @tagName(kind), @tagName(token.kind) });
        std.debug.print("{s}\n", .{source});

        return error.UnexpectedToken;
    }

    self.curr_token += 1;
}

fn expect(self: *Self, tokens: []Tokenizer.Token, kind: Tokenizer.TokenKind) !void {
    if (self.curr_token >= tokens.len) {
        std.debug.print("Expected token of type {s}, but got EOF\n", .{@tagName(kind)});
        return error.UnexpectedToken;
    }

    const token = tokens[self.curr_token];

    if (token.kind != kind) {
        const location = self.get_source_location(token);
        const source = self.get_source_string(token);

        std.debug.print("{}:{}: Expected token of type {s}, but got {s}\n", .{ location.line, location.column, @tagName(kind), @tagName(token.kind) });
        std.debug.print("{s}\n", .{source});

        return error.UnexpectedToken;
    }
}

pub fn create(source: []const u8) Self {
    return Self{
        .source = source,
    };
}

fn parse_fields(self: *Self, tokens: []Tokenizer.Token) ![]Field {
    var fields = std.ArrayList(Field).init(util.allocator());

    try self.expect(tokens, .LSquirly);
    self.curr_token += 1;

    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        // Check if we are at the end of the fields
        if (tokens[self.curr_token].kind == .RSquirly) {
            break;
        }

        // Parse field
        try self.expect(tokens, .Ident);

        // Grab field name
        const name: Index = @intCast(self.curr_token);

        // Consume colon
        try self.expect_next(tokens, .Colon);

        // Grab field type

        if (self.curr_token + 1 < tokens.len) {
            if (tokens[self.curr_token + 1].kind == .KWEvent) {
                try self.expect_next(tokens, .KWEvent);
                const kind: Index = @intCast(self.curr_token);

                // Consume opening paren
                try self.expect_next(tokens, .LParen);
                // Consume ident
                try self.expect_next(tokens, .Ident);
                // Consume closing paren
                try self.expect_next(tokens, .RParen);

                try fields.append(.{ .name = name, .kind = kind, .len_kind = 3 });
                continue;
            }
        }

        try self.expect_next(tokens, .Ident);
        const kind: Index = @intCast(self.curr_token);

        try fields.append(.{ .name = name, .kind = kind });
    }

    return try fields.toOwnedSlice();
}

fn parse_attributes(self: *Self, tokens: []Tokenizer.Token) ![]Attribute {
    var attributes = std.ArrayList(Attribute).init(util.allocator());
    self.curr_token += 1;

    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        const token = tokens[self.curr_token];

        // Check if we are at the end of the attributes
        if (token.kind == .LSquirly) {
            self.curr_token -= 1;
            break;
        }

        // Parse attribute
        const kind = switch (token.kind) {
            .KWEnum => AttributeType.Enum,
            .KWIn => AttributeType.InEvent,
            .KWOut => AttributeType.OutEvent,
            .KWInOut => AttributeType.InOutEvent,
            .KWCompressed => AttributeType.Compressed,
            .KWEncrypted => AttributeType.Encrypted,
            .KWStateEvent => AttributeType.State,
            else => {
                std.debug.print("Unexpected token {}\n", .{token});
                self.print_source(token);
                return error.UnexpectedToken;
            },
        };

        // Consume attribute value
        try self.expect_next(tokens, .LParen);
        try self.expect_next(tokens, .Ident);

        // Grab index
        const index: Index = @intCast(self.curr_token);

        // Consume closing parenthesis
        try self.expect_next(tokens, .RParen);

        // Add attribute
        try attributes.append(.{ .type = kind, .value = index });
    }

    return try attributes.toOwnedSlice();
}

pub fn parse(self: *Self, tokens: []Tokenizer.Token) !Protocol {
    std.debug.print("\rParsing protocol...", .{});
    var proto: Protocol = .{
        .entries = std.ArrayList(Entry).init(util.allocator()),
    };

    while (self.curr_token < tokens.len) : (self.curr_token += 1) {
        const token = tokens[self.curr_token];

        if (token.kind == .KWEndian) { // Set endianness
            try self.expect_next(tokens, .Ident);

            // Grab next token
            const ident = tokens[self.curr_token];
            if (std.mem.eql(u8, self.source[ident.start .. ident.start + ident.len], "little")) {
                proto.endian = .Little;
            } else if (std.mem.eql(u8, self.source[ident.start .. ident.start + ident.len], "big")) {
                proto.endian = .Big;
            } else {
                std.debug.print("Expected 'little' or 'big' after '@endian', but got {s}\n", .{self.get_source_string(ident)});
                return error.InvalidEndian;
            }
        } else if (token.kind == .KWDirection) { // Set direction
            try self.expect_next(tokens, .Ident);

            const ident = tokens[self.curr_token];
            if (std.mem.eql(u8, self.source[ident.start .. ident.start + ident.len], "in")) {
                proto.direction = .In;
            } else if (std.mem.eql(u8, self.source[ident.start .. ident.start + ident.len], "out")) {
                proto.direction = .Out;
            } else {
                std.debug.print("Expected 'in' or 'out' after '@direction', but got {s}\n", .{self.get_source_string(ident)});
                return error.InvalidDirection;
            }
        } else if (token.kind == .KWState or token.kind == .KWPacket or token.kind == .Ident) { // Entries
            var entry: Entry = .{
                .name = @intCast(self.curr_token),
                .fields = &[_]Field{},
            };

            // Check if this is a state or packet
            if (token.kind == .KWState) {
                entry.special = .State;
            } else if (token.kind == .KWPacket) {
                entry.special = .Packet;
            }

            // States cannot have attributes
            if (token.kind == .KWState) {
                if (self.curr_token + 1 < tokens.len) {
                    const next_token = tokens[self.curr_token + 1];
                    if (next_token.kind == .Colon) {
                        std.debug.print("State attributes are not supported yet!\n", .{});
                        return error.UnsupportedStateAttributes;
                    }
                }
            } else {
                // Parse attributes if any are present
                if (self.curr_token + 1 < tokens.len) {
                    const next_token = tokens[self.curr_token + 1];
                    if (next_token.kind == .Colon) {
                        // Consume colon
                        try self.expect_next(tokens, .Colon);

                        // Attributes detected, parse
                        entry.attributes = try self.parse_attributes(tokens);
                    }
                }
            }

            try self.expect_next(tokens, .LSquirly);
            entry.fields = try self.parse_fields(tokens);
            try self.expect(tokens, .RSquirly);

            try proto.entries.append(entry);
        } else if (token.kind == .EOF) {
            break;
        } else {
            const location = self.get_source_location(token);

            std.debug.print("Unexpected token {}\n", .{token});
            std.debug.print("At line {}, column {}\n", .{ location.line, location.column });

            std.debug.print("Proto: {}\n", .{proto});
            return error.UnexpectedToken;
        }
    }

    return proto;
}
