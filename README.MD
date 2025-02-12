# ZeeBuffer

ZeeBuffer is a cross-platform protocol specification language for serializing and deserializing structured data in a stateful client-server connection.

It produces bindings in Zig currently, although [a C code generator is planned](https://github.com/IridescentRose/ZeeBuffer/issues/7)

# Why use ZeeBuffer

Use ZeeBuffer if:
* Integrating with existing applications or the existing protocol cannot be modified (useful for RE)
* Endianness may differ between sides of the connection, or is necessary to swap
* Connections don't necessarily need to be socket based; e.g. SPI, UART, etc.

ZeeBuffer is:
* Multiplatform, with no platform-specific dependencies
* Small, with a single file generated of code
* Routable, with an interface to easily read packets and pass them to their respective handlers
* Easy to use, with each structure being converted from network to native and back when necessary

# Usage

The [protocol](./design/Language.MD) is defined in the `.zb` protocol file. This protocol is a single file that defines the messages that can be sent between the client and server. The protocol file is then compiled to the target language using the `zbc` compiler. The compiler generates code that can be used to send and receive messages in the target language.

# Example Schema

```zb
@endian big

WeatherType : Enum(u8) {
    Sunny: 1,
    Cloudy: 2,
    Rainy: 3,
}

@state {
    Handshake: 0,
    Login: 1,
    Status: 2,
    Play: 3,
}

Vec3 {
    x: f64,
    y: f64,
    z: f64,
}

HandshakeEventIDs : Enum(u8) {
    HandshakeID: 0,
    TransitionID: 1,
}

HandshakeClient: Event(HandshakeID, Handshake, Client) {
    protocolVersion: u32,
    username: Array(u8, 16),
    key: Array(u8, 32),
}

HandshakeServer: Event(HandshakeID, Handshake, Server) {
    protocolVersion: u32,
    serverAddress: Array(u8, 16),
    serverPort: u16,
}

TransitionBoth: Event(TransitionID, Handshake, Both) {
    desiredState: u8,
}
```

# Example Program

```zig
const std = @import("std");
const zb = @import("zeebuffer.zig"); // Include generated file

fn handshake(ctx: ?*anyopaque, event: *zb.HandshakeClient) anyerror!void {
     // Process handshake packet from client
}

pub fn main() !void {
    const allocator = // ...
    var reader = // Anything with an AnyReader interface
    var writer = // Anything with an AnyWriter interface

    var pid: u32 = 1337; // Some data that needs to be shared

    // Role = Receive From X (In this case client)
    var proto = zb.Protocol.init(.Client, .Connected, &pid);

    while(true) {
        var id = // Receive from source / determine what message this is
        var buffer = // Packet buffer as described by protocol
        try proto.handle_packet(buffer, id);
    }
}

```

# ¿Parker Jones?

Thank you for helping design the initial version of the protocol DSL!
