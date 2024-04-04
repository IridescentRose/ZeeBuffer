const std = @import("std");
const zeebuffer = @import("out.zig");

pub fn main() !void {
    const input = [_]u8{ 5, 1, 32, 13, 37, 3 };
    var output = std.mem.zeroes([1024]u8);

    var istream = std.io.fixedBufferStream(input[0..]);
    var ostream = std.io.fixedBufferStream(output[0..]);

    const reader = istream.reader().any();
    const writer = ostream.writer().any();

    var proto = zeebuffer.Protocol.init(.{}, reader, writer);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    try proto.poll(allocator);
}
