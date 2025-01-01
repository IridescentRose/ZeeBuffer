const std = @import("std");
const assert = std.debug.assert;

const util = @import("util.zig");
const Tokenizer = @import("frontend/tokenizer.zig");

const Self = @This();

pub const Location = packed struct(u64) {
    line: u32,
    column: u32,
};

/// Source text of the file.
source: []const u8,

/// Tokens of the file.
tokens: []const Tokenizer.Token,

/// Read the file at the given path and tokenize it.
pub fn init(path: []const u8) !Self {
    const source = try read_file(path);

    var tokenizer = Tokenizer.init(source);

    return .{
        .source = source,
        .tokens = try tokenizer.tokenize(),
    };
}

/// Reads the file at the given path and returns its contents.
fn read_file(path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(
        util.allocator(),
        std.math.maxInt(u32),
    );
}

pub fn get_token_text(self: Self, token: Tokenizer.Token) []const u8 {
    return self.source[token.start..(token.start + token.len)];
}

pub fn get_token_text_by_idx(self: Self, idx: u16) []const u8 {
    return self.get_token_text(self.tokens[idx]);
}

// Pull location for error messages
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

// Pull context window for error messages
// TODO: This sometimes bugs out
pub fn get_source_string(self: *Self, token: Tokenizer.Token) []const u8 {
    const WINDOW_SIZE = 64;
    const start = if (token.start < WINDOW_SIZE) 0 else token.start - WINDOW_SIZE;
    const end = if (token.start + token.len + WINDOW_SIZE > self.source.len) self.source.len else token.start + token.len + WINDOW_SIZE;

    const startNewLine = token.start - (std.mem.indexOf(u8, self.source[start..token.start], "\n") orelse 0);
    const endNewLine = (std.mem.indexOf(u8, self.source[token.start..end], "\n") orelse 0) + token.start;

    return self.source[startNewLine..endNewLine];
}
