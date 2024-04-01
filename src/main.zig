const std = @import("std");

const fs = std.fs;
const log = std.log;
const testing = std.testing;

const util = @import("util.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");

/// Returns the file name from the command-line arguments.
fn parse_args() !?[]const u8 {
    // Get the command-line arguments.
    const allocator = util.allocator();
    var arg_it = try std.process.argsWithAllocator(allocator);
    defer arg_it.deinit();

    // Skip the first argument, which is the program name.
    _ = arg_it.skip();

    // First argument is the file.
    const file = arg_it.next();

    // If no file was provided, print usage and return.
    if (file == null) {
        log.err("Usage: zbc <filename>", .{});
        return null;
    }

    // Not sure if duping is necessary, but arg_it.deinit()
    // should free the memory making it possibly invalid.
    return try allocator.dupe(u8, file.?);
}

// Reads the file bytes into a buffer
fn read_file(path: []const u8) ![]const u8 {
    // Open and read the file.
    var file = try fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(
        util.allocator(),
        std.math.maxInt(u32),
    );
}

pub fn main() !void {
    util.init();
    defer util.deinit();

    const file = try parse_args();

    if (file == null) {
        return;
    }

    const contents = try read_file(file.?);
    var tokenizer = try Tokenizer.create(contents);

    const tokens = try tokenizer.tokenize();

    var parser = Parser.create(contents);
    const tree = parser.parse(tokens) catch return;

    log.debug("{}", .{tree});
}

test "tokenize" {
    const source = "foo: bar, baz: qux";
    var tokenizer = try Tokenizer.create(source);
    const tokens = try tokenizer.tokenize();
    const expected = [_]Tokenizer.Token{
        .{ .kind = .Ident, .start = 0 },
        .{ .kind = .Colon, .start = 3 },
        .{ .kind = .Ident, .start = 5 },
        .{ .kind = .Comma, .start = 8 },
        .{ .kind = .Ident, .start = 10 },
        .{ .kind = .Colon, .start = 13 },
        .{ .kind = .Ident, .start = 15 },
        .{ .kind = .EOF, .start = 18 },
    };

    for (tokens, expected[0..]) |token, expect| {
        try std.testing.expectEqual(expect, token);
    }
}
test "tokenize_schema_kw" {
    const source = "mything : Event(1) { time: u64 }";
    var tokenizer = try Tokenizer.create(source);
    const tokens = try tokenizer.tokenize();
    const expected = [_]Tokenizer.Token{
        .{ .kind = .Ident, .start = 0 },
        .{ .kind = .Colon, .start = 8 },
        .{ .kind = .KWEvent, .start = 10 },
        .{ .kind = .LParen, .start = 15 },
        .{ .kind = .Ident, .start = 16 },
        .{ .kind = .RParen, .start = 17 },
        .{ .kind = .LSquirly, .start = 19 },
        .{ .kind = .Ident, .start = 21 },
        .{ .kind = .Colon, .start = 25 },
        .{ .kind = .Ident, .start = 27 },
        .{ .kind = .RSquirly, .start = 31 },
        .{ .kind = .EOF, .start = 32 },
    };

    for (tokens, expected[0..]) |token, expect| {
        try std.testing.expectEqual(expect, token);
    }
}
