const std = @import("std");
const zeebuffer = @import("out.zig");

fn handshake(ctx: ?*anyopaque, event: *zeebuffer.OutHandshakeHandshake) anyerror!void {
    const pid: *u32 = @ptrCast(@alignCast(ctx.?));

    std.debug.print("Handshake: {}\n", .{pid.*});

    std.debug.print("Protocol: {}\n", .{event.protocolVersion});
    std.debug.print("Server: {s}\n", .{event.serverAddress});
    std.debug.print("Port: {}\n", .{event.serverPort});
    std.debug.print("Username: {s}\n", .{event.username});
}

pub fn main() !void {
    const username = "TestUser";
    const usernameBuf = username ++ [_]u8{0} ** (16 - username.len);

    var pid: u32 = 1337;

    const blob = [_]u8{ 1, 32, 8 } ++ "test.com" ++ usernameBuf ++ [_]u8{ 13, 37, 3 };
    const input = [_]u8{blob.len} ++ blob;
    var output = std.mem.zeroes([1024]u8);

    var istream = std.io.fixedBufferStream(input[0..]);
    var ostream = std.io.fixedBufferStream(output[0..]);

    const reader = istream.reader().any();
    const writer = ostream.writer().any();

    var proto = zeebuffer.Protocol.init(.{
        .OutHandshakeHandshake_handler = handshake,
    }, reader, writer);
    proto.user_context = @ptrCast(std.mem.asBytes(&pid));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    try proto.poll(allocator);
}
