const std = @import("std");
const Io = std.Io;

pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const lower = @import("lower.zig");
pub const zig_gen = @import("codegen/zig.zig");

comptime {
    _ = std.testing.refAllDecls(@This());
}

const usage =
    \\Usage: zbc <in_file> <out_file> [-target <language>]
    \\
    \\Options:
    \\  -target <language>   Output language: Zig (default), C
    \\
;

const Target = enum { Zig, C };

const Args = struct {
    in_file: []const u8,
    out_file: []const u8,
    target: Target,
};

fn parseArgs(argv: []const []const u8, stderr: *Io.Writer) !Args {
    var in_file: ?[]const u8 = null;
    var out_file: ?[]const u8 = null;
    var target: Target = .Zig;

    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "-target")) {
            i += 1;
            if (i >= argv.len) {
                try stderr.print("error: -target requires a language argument\n\n{s}", .{usage});
                try stderr.flush();
                std.process.exit(1);
            }
            const lang = argv[i];
            if (std.mem.eql(u8, lang, "Zig")) {
                target = .Zig;
            } else if (std.mem.eql(u8, lang, "C")) {
                target = .C;
            } else {
                try stderr.print("error: unknown target '{s}' (supported: Zig, C)\n\n{s}", .{ lang, usage });
                try stderr.flush();
                std.process.exit(1);
            }
        } else if (in_file == null) {
            in_file = arg;
        } else if (out_file == null) {
            out_file = arg;
        } else {
            try stderr.print("error: unexpected argument '{s}'\n\n{s}", .{ arg, usage });
            try stderr.flush();
            std.process.exit(1);
        }
    }

    if (in_file == null or out_file == null) {
        try stderr.print("error: in_file and out_file are required\n\n{s}", .{usage});
        try stderr.flush();
        std.process.exit(1);
    }

    return .{ .in_file = in_file.?, .out_file = out_file.?, .target = target };
}

fn readFile(io: Io, path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &file_buffer);
    const size = try reader.getSize();

    if (size > std.math.maxInt(u16)) {
        return error.FileTooLarge;
    }

    return reader.interface.readAlloc(allocator, size);
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const raw_args = try init.minimal.args.toSlice(arena);
    // raw_args[0] is the executable name; skip it.
    if (raw_args.len <= 1) {
        try stderr.print("{s}", .{usage});
        try stderr.flush();
        std.process.exit(1);
    }

    const args = try parseArgs(raw_args[1..], stderr);
    try stderr.flush();

    // TODO: Implement C target
    if (args.target == .C) {
        try stderr.print("error: C target is not yet implemented\n", .{});
        try stderr.flush();
        std.process.exit(1);
    }

    // Main compilation logic
    const source = try readFile(io, args.in_file, arena);
    const tokens = try lexer.tokenize(arena, source);
    const ast = try parser.parse(arena, tokens, source);
    var ast_mut = ast;
    const ir = try lower.lower(arena, &ast_mut);
    try ir.verify();

    var out_file = try std.Io.Dir.cwd().createFile(io, args.out_file, .{});
    var out_buffer: [4096]u8 = undefined;
    var out_writer = out_file.writer(io, &out_buffer);

    switch (args.target) {
        .Zig => try zig_gen.emit(&ir, &out_writer.interface),
        else => {},
    }

    try out_writer.flush();

    try stdout.flush();
}
