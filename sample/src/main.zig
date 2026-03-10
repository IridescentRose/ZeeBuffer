const std = @import("std");
const log = std.log.scoped(.server);
const Io = std.Io;

const protocol = @import("protocol");

pub const Client = struct {
    stream: std.Io.net.Stream,
    protocol: protocol.Protocol,

    fn playerIDRequestHandler(ctx: *anyopaque, event: protocol.PlayerIDRequest) !void {
        _ = ctx;
        log.info("Player ID Request:", .{});
        log.info("Username: {s}", .{event.username});
        log.info("Key:      {s}", .{event.key});
        log.info("Protocol: {d}", .{event.protocol_version});
    }

    pub fn run(self: *Client, io: std.Io) !void {
        var packet_buffer: [1028]u8 = undefined;

        self.protocol = .init(.client, .Connected, self);
        self.protocol.handles.onPlayerIDRequest = playerIDRequestHandler;

        while (true) {
            var id: u8 = 0;
            _ = try self.stream.socket.receive(io, std.mem.asBytes(&id));

            var slice: []u8 = packet_buffer[0..];
            if (id == 0) {
                slice = packet_buffer[0..130];
            }

            _ = try self.stream.socket.receive(io, slice);
            _ = try self.protocol.handle_packet(slice, id);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    const io = init.io;

    log.info("Starting server...", .{});

    const server_ip = try std.Io.net.IpAddress.parseIp4("0.0.0.0", 25565);
    var server = try server_ip.listen(io, .{});
    defer server.deinit(io);

    while (true) {
        var conn = try server.accept(io);
        log.info("Client connected: {}", .{conn.socket.address});

        const client = try arena.create(Client);
        client.stream = conn;

        _ = try std.Thread.spawn(.{}, Client.run, .{ client, io });
    }
}
