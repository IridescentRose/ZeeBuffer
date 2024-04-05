const std = @import("std");

const fs = std.fs;
const testing = std.testing;

const util = @import("util.zig");
const Tree = @import("AST.zig");
const Tokenizer = @import("frontend/Tokenizer.zig");
const SourceObject = @import("SourceObject.zig");
const Parser = @import("frontend/Parser.zig");
const SemanticAnalysis = @import("frontend/Sema.zig");
const CodeGen = @import("codegen.zig");

// Input file
var in_file: ?[]const u8 = null;

// Output file
var out_file: ?[]const u8 = null;

fn parse_args() !void {
    // Get the command-line arguments.
    var arg_it = try std.process.argsWithAllocator(util.allocator());

    // Skip the program name
    _ = arg_it.skip();

    in_file = arg_it.next();
    out_file = arg_it.next();

    // If no file was provided, print usage and return.
    if (in_file == null or out_file == null) {
        std.debug.print("Usage: zbc <infile> <outfile>\n", .{});
        return error.MissingArgument;
    }
}

pub fn main() !void {
    util.init();
    defer util.deinit();

    // Parse arguments
    // TODO: Better argument parsing
    parse_args() catch return;

    // Frontend: Tokenize, parse, and analyze the input
    const source_obj = try SourceObject.init(in_file.?);

    var parser = Parser.init(source_obj);
    const AST = parser.parse() catch return;

    var sema = SemanticAnalysis.init(source_obj);
    const IR = try sema.analyze(AST);

    // Backend: Code generation
    var output_buffer = std.ArrayList(u8).init(util.allocator());
    var bw = std.io.bufferedWriter(output_buffer.writer());

    var codegen = CodeGen.init(IR);
    try codegen.generate(bw.writer());

    // Write the output to the file
    try bw.flush();

    var output_file = try fs.cwd().createFile(out_file.?, .{});
    defer output_file.close();

    _ = try output_file.write(try output_buffer.toOwnedSlice());
}

test "example" {
    const source_obj = try SourceObject.init("test/example.zb");

    var parser = Parser.init(source_obj);
    const AST = parser.parse() catch return;

    var sema = SemanticAnalysis.init(source_obj);
    _ = try sema.analyze(AST);
}

test "tokenize" {
    const source_obj = try SourceObject.init("test/test_tokenize.zb");

    const token_list = [_]Tokenizer.Token{
        .{
            .kind = .KWEndian,
            .start = 0,
            .len = 7,
        },
        .{
            .kind = .Ident,
            .start = 8,
            .len = 6,
        },
        .{
            .kind = .KWDirection,
            .start = 15,
            .len = 10,
        },
        .{
            .kind = .Ident,
            .start = 26,
            .len = 2,
        },
        .{
            .kind = .KWState,
            .start = 31,
            .len = 6,
        },
        .{
            .kind = .LSquirly,
            .start = 38,
            .len = 1,
        },
        .{
            .kind = .Ident,
            .start = 44,
            .len = 9,
        },
        .{
            .kind = .Colon,
            .start = 54,
            .len = 1,
        },
        .{
            .kind = .Ident,
            .start = 56,
            .len = 1,
        },
        .{
            .kind = .RSquirly,
            .start = 59,
            .len = 1,
        },
        .{
            .kind = .EOF,
            .start = 60,
        },
    };

    for (source_obj.tokens, token_list) |token, expected| {
        try testing.expectEqual(expected, token);
    }
}

test "parse_succeed" {
    const source_obj = try SourceObject.init("test/test_parse.zb");

    var parser = Parser.init(source_obj);
    const AST = try parser.parse();

    try testing.expectEqual(.Little, AST.endian);
    try testing.expectEqual(.In, AST.direction);

    try testing.expectEqual(4, AST.entries[0].name);
    try testing.expectEqual(.State, AST.entries[0].special);

    try testing.expectEqual(10, AST.entries[1].name);
    try testing.expectEqual(.Packet, AST.entries[1].special);
}

test "parse_fail_state" {
    const source_obj = try SourceObject.init("test/test_parse_fail_state.zb");

    var parser = Parser.init(source_obj);

    try testing.expectError(error.SyntaxStateAttributes, parser.parse());
}

test "parse_fail_eof" {
    const source_obj = try SourceObject.init("test/test_parse_fail_eof.zb");

    var parser = Parser.init(source_obj);

    try testing.expectError(error.SyntaxUnexpectedToken, parser.parse());
}

test "sema_state_not_found" {
    const source_obj = try SourceObject.init("test/test_sema_state_no.zb");

    var parser = Parser.init(source_obj);
    const AST = try parser.parse();

    var sema = SemanticAnalysis.init(source_obj);

    try testing.expectError(error.SemanticStateNotDefined, sema.analyze(AST));
}

test "sema_state_redefined" {
    const source_obj = try SourceObject.init("test/test_sema_state_redefine.zb");

    var parser = Parser.init(source_obj);
    const AST = try parser.parse();

    var sema = SemanticAnalysis.init(source_obj);

    try testing.expectError(error.SemanticStateRedefinition, sema.analyze(AST));
}

test "sema_state_missing" {
    const source_obj = try SourceObject.init("test/test_sema_state_missing.zb");

    var parser = Parser.init(source_obj);
    const AST = try parser.parse();

    var sema = SemanticAnalysis.init(source_obj);

    try testing.expectError(error.SemanticStateNotFound, sema.analyze(AST));
}

test "sema_type_missing" {
    const source_obj = try SourceObject.init("test/test_sema_type_missing.zb");

    var parser = Parser.init(source_obj);
    const AST = try parser.parse();

    var sema = SemanticAnalysis.init(source_obj);

    try testing.expectError(error.SemanticTypeNotFound, sema.analyze(AST));
}
test "sema_enum_type" {
    const source_obj = try SourceObject.init("test/test_sema_enum_type.zb");

    var parser = Parser.init(source_obj);
    const AST = try parser.parse();

    var sema = SemanticAnalysis.init(source_obj);

    try testing.expectError(error.SemanticEnumBackingTypeNotFound, sema.analyze(AST));
}
