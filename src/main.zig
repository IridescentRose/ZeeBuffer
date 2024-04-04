const std = @import("std");

const fs = std.fs;
const testing = std.testing;

const util = @import("util.zig");
const SourceObject = @import("SourceObject.zig");
const Parser = @import("Parser.zig");
const SemanticAnalysis = @import("sema.zig");
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
    parse_args() catch return;

    // Frontend: Tokenize, parse, and analyze the input
    const source_obj = try SourceObject.init(in_file.?);

    var parser = Parser.init(source_obj);
    const AST = parser.parse() catch return;

    var sema = try SemanticAnalysis.create(source_obj);
    try sema.analyze(AST);

    // Backend: Code generation
    var output_buffer = std.ArrayList(u8).init(util.allocator());
    var bw = std.io.bufferedWriter(output_buffer.writer());

    var codegen = try CodeGen.create(sema);
    try codegen.generate(bw.writer());

    // Write the output to the file
    try bw.flush();

    var output_file = try fs.cwd().createFile(out_file.?, .{});
    defer output_file.close();

    _ = try output_file.write(try output_buffer.toOwnedSlice());

    std.debug.print("\r                           \n", .{});
}
