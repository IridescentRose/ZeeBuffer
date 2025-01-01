const std = @import("std");
const log = std.log;
const posix = std.posix;
const builtin = @import("builtin");
const protocol = @import("protocol");

const Client = struct {
    socket: posix.socket_t,
    address: posix.sockaddr.in,
    protocol: protocol.Protocol,

    pub fn init(socket: posix.socket_t, address: posix.sockaddr.in) Client {
        return .{
            .socket = socket,
            .address = address,
            .protocol = undefined,
        };
    }

    fn playerIDToServer(self: *anyopaque, event: protocol.PlayerIDToServer) !void {
        _ = self;
        std.debug.print("PlayerIDToServer\n", .{});

        std.debug.print("Username: {s}\n", .{event.username});
        std.debug.print("Key: {s}\n", .{event.key});
        std.debug.print("Protocol Version: {}\n", .{event.protocol_version});
    }

    pub fn run(self: *Client) !void {
        std.debug.print("Client thread started\n", .{});
        std.debug.print("Client from port {}\n", .{@byteSwap(self.address.port)});

        self.protocol = protocol.Protocol.init(.Client, .Connected, self);
        self.protocol.handle.handle_PlayerIDToServer = playerIDToServer;

        var packet_buffer: [1028]u8 = undefined;

        while (true) {
            var id: u8 = 0;
            _ = try posix.recv(self.socket, std.mem.asBytes(&id), 0);

            var slice: []u8 = packet_buffer[0..];
            if (id == 0) {
                slice = packet_buffer[0..130];
            }

            _ = try posix.recv(self.socket, slice, 0);
            _ = try self.protocol.handle_packet(slice, id);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    log.info("Starting server...", .{});

    if (builtin.os.tag == .windows) {
        _ = try std.os.windows.WSAStartup(2, 2);
    }

    const socket = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);

    const true_flag: u32 = 1;

    if (builtin.os.tag == .windows) {
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(true_flag));
    } else {
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.REUSEPORT, &std.mem.toBytes(true_flag));
    }

    // Bind to localhost:25565
    const ip: u32 = 0x7F000001;
    const port: u16 = 25565;

    const addr = posix.sockaddr.in{ .port = @byteSwap(port), .addr = @byteSwap(ip) };

    try posix.bind(socket, @ptrCast(&addr), @sizeOf(posix.sockaddr.in));

    try posix.listen(socket, 1);

    while (true) {
        var address: posix.sockaddr.in = undefined;
        var addr_len: u32 = @sizeOf(posix.sockaddr.in);

        const client_socket = try posix.accept(socket, @ptrCast(&address), &addr_len, 0);

        const client_addr = std.mem.toBytes(address.addr);
        log.info("Accepted connection from {}.{}.{}.{}:{}", .{ client_addr[0], client_addr[1], client_addr[2], client_addr[3], @byteSwap(address.port) });

        const client = try allocator.create(Client);
        client.* = Client.init(client_socket, address);

        _ = try std.Thread.spawn(.{}, Client.run, .{client});
    }
}
