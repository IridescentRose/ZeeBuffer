const std = @import("std");
const util = @import("util.zig");
const Tokenizer = @import("Tokenizer.zig");

const Self = @This();

source: []const u8,
tokens: []const Tokenizer.Token,

// Source location
pub const Location = struct {
    line: u32,
    column: u32,
};

// Initialize the object by reading the file and tokenizing it
pub fn init(path: []const u8) !Self {
    const source = try Self.read_file(path);
    var tokenizer = try Tokenizer.create(source);

    return Self{
        .source = source,
        .tokens = try tokenizer.tokenize(),
    };
}

pub fn get_source_location(self: *Self, token: Tokenizer.Token) Location {
    var line: u32 = 1;
    var column: u32 = 1;

    for (self.source[0..token.start]) |c| {
        if (c == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

pub fn get_source_string(self: *Self, token: Tokenizer.Token) []const u8 {
    const WINDOW_SIZE = 64;
    const start = if (token.start - WINDOW_SIZE < 0) 0 else token.start - WINDOW_SIZE;
    const end = if (token.start + token.len + WINDOW_SIZE > self.source.len) self.source.len else token.start + token.len + WINDOW_SIZE;

    const startNewLine = token.start - (std.mem.indexOf(u8, self.source[start..token.start], "\n") orelse 0);
    const endNewLine = (std.mem.indexOf(u8, self.source[token.start..end], "\n") orelse 0) + token.start;

    return self.source[startNewLine..endNewLine];
}

pub fn print_source(self: *Self, token: Tokenizer.Token) void {
    const location = self.get_source_location(token);
    const source = self.get_source_string(token);

    std.debug.print("{}:{}:\n", .{ location.line, location.column });
    std.debug.print("{s}\n", .{source});
}

pub fn token_text(self: *Self, token: Tokenizer.Token) []const u8 {
    return self.source[token.start .. token.start + token.len];
}

pub fn token_text_idx(self: *Self, idx: u16) []const u8 {
    return self.token_text(self.tokens[idx]);
}

// Reads the file bytes into a buffer
fn read_file(path: []const u8) ![]const u8 {
    // Open and read the file.
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(
        util.allocator(),
        std.math.maxInt(u32),
    );
}
