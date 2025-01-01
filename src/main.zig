const std = @import("std");
const util = @import("util.zig");

const SourceObject = @import("SourceObject.zig");
const Parser = @import("frontend/parser.zig");
const Sema = @import("frontend/sema.zig");

const Codegen = @import("backend/codegen.zig");

var in_file: ?[]const u8 = null;
var out_file: ?[]const u8 = null;

fn parse_args() !void {
    var arg_it = try std.process.argsWithAllocator(util.allocator());

    _ = arg_it.skip();

    in_file = arg_it.next();
    out_file = arg_it.next();

    if (in_file == null or out_file == null) {
        std.debug.print("Usage: zbc <in_file> <out_file>\n", .{});
        std.posix.exit(1); // Don't care about cleanup -- we're exiting anyway
    }
}

pub fn main() !void {
    util.init();
    defer util.deinit();

    try parse_args();

    const source = try SourceObject.init(in_file.?);

    var parser = Parser.init(source);
    const ast = try parser.parse();

    var sema = Sema.init(ast, source);
    const ir = try sema.analyze();

    try Codegen.generate_code(&ir, out_file.?, .Zig);
}
