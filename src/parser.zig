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
};

pub const Entry = struct {
    name: Index,
    packet: bool = false,
    state: bool = false,
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
    stateCount: u16 = 0,
    entries: []Entry,
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
    const start = if (token.start - 16 < 0) 0 else token.start - 16;
    const end = if (token.start + token.len + 16 > self.source.len) self.source.len else token.start + token.len + 16;

    return self.source[start..end];
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

pub fn create(source: []const u8) Self {
    return Self{
        .source = source,
    };
}

fn parse_attributes(self: *Self, tokens: []Tokenizer.Token) ![]Attribute {
    _ = self;
    _ = tokens;
    var attributes = std.ArrayList(Attribute).init(util.allocator());

    // TODO: Parse attributes

    return try attributes.toOwnedSlice();
}

pub fn parse(self: *Self, tokens: []Tokenizer.Token) !Protocol {
    var proto: Protocol = .{
        .entries = &[_]Entry{},
    };

    var entries = std.ArrayList(Entry).init(util.allocator());

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
                proto.stateCount += 1;
                entry.state = true;
            } else if (token.kind == .KWPacket) {
                entry.packet = true;
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
            // TODO: Parse fields
            try self.expect_next(tokens, .RSquirly);

            try entries.append(entry);
        } else {
            const location = self.get_source_location(token);

            std.debug.print("Unexpected token {}\n", .{token});
            std.debug.print("At line {}, column {}\n", .{ location.line, location.column });

            std.debug.print("Proto: {}\n", .{proto});
            return error.UnexpectedToken;
        }
    }

    proto.entries = try entries.toOwnedSlice();
    return proto;
}
