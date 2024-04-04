const std = @import("std");

const fs = std.fs;
const log = std.log;
const testing = std.testing;

const util = @import("util.zig");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const SemanticAnalysis = @import("sema.zig");
const CodeGen = @import("codegen.zig");

var in_file: ?[]const u8 = null;
var out_file: ?[]const u8 = null;

/// Returns the file name from the command-line arguments.
fn parse_args() !?void {
    // Get the command-line arguments.
    const allocator = util.allocator();
    var arg_it = try std.process.argsWithAllocator(allocator);
    defer arg_it.deinit();

    // Skip the first argument, which is the program name.
    _ = arg_it.skip();

    // First argument is the file.
    in_file = arg_it.next();

    // If no file was provided, print usage and return.
    if (in_file == null) {
        log.err("Usage: zbc <infile> <outfile>", .{});
        return null;
    }

    // Second argument is the output.
    out_file = arg_it.next();

    // If no file was provided, print usage and return.
    if (out_file == null) {
        log.err("Usage: zbc <infile> <outfile>", .{});
        return null;
    }

    // Not sure if duping is necessary, but arg_it.deinit()
    // should free the memory making it possibly invalid.
    return;
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

fn count_lines(contents: []const u8) u32 {
    var lines: u32 = 1;
    for (contents) |c| {
        if (c == '\n') {
            lines += 1;
        }
    }
    return lines;
}

pub fn main() !void {
    util.init();
    defer util.deinit();

    const start = std.time.nanoTimestamp();

    const result = try parse_args();

    if (result == null) {
        return;
    }

    const contents = try read_file(in_file.?);

    const lines = count_lines(contents);

    var tokenizer = try Tokenizer.create(contents);
    const tokens = try tokenizer.tokenize();

    var parser = Parser.create(contents);
    var tree = parser.parse(tokens) catch return;

    var sema = try SemanticAnalysis.create(contents, tokens);
    try sema.analyze(&tree);

    const f_end = std.time.nanoTimestamp();

    const f_elapsed = @as(f64, @floatFromInt(f_end - start)) / 1000_0000_0000.0;
    const f_locs = @as(f64, @floatFromInt(lines)) / f_elapsed / 1000_000.0;
    std.debug.print("\nFrontend: {d:.3} MLoC/s\n", .{f_locs});

    // Code generation
    var output_buffer = std.ArrayList(u8).init(util.allocator());
    const ow = output_buffer.writer();

    var bw = std.io.bufferedWriter(ow);
    const writer = bw.writer();

    var codegen = try CodeGen.create(sema);
    try codegen.generate(writer);

    try bw.flush();

    var output_file = try fs.cwd().createFile(out_file.?, .{});
    defer output_file.close();

    _ = try output_file.write(try output_buffer.toOwnedSlice());

    std.debug.print("\n", .{});
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
