# ZeeBuffers

ZeeBuffers is a cross-platform protocol specification language for serializing and deserializing structured data in a stateful client-server connection.

It produces bindings in Zig currently, although [a C code generator is planned](https://github.com/IridescentRose/ZeeBuffer/issues/7)

# Why use ZeeBuffers

Use ZeeBuffers if:
* Integrating with existing applications or the existing protocol cannot be modified
* A protocol requires parsing/unpacking and repacking in specific ways
* Endianness may differ between sides of the connection, or is necessary to swap
* Connections don't necessarily need to be socket based; e.g. SPI, UART, etc.

ZeeBuffers is:
* Multiplatform, with no platform-specific dependencies
* Small, with a single file generated of code
* Routable, with an interface to easily read packets and pass them to their respective handlers
* Easy to use, with each structure being converted from network to native and back when necessary

# Usage

The [protocol](./PROTOCOL.MD) is defined in the `.zb` protocol file. This protocol is a single file that defines the messages that can be sent between the client and server. The protocol file is then compiled to the target language using the `zbc` compiler. The compiler generates code that can be used to send and receive messages in the target language.

# Example Schema

```zb
@endian big
@direction in

@state {
    Handshake: 0,
    Connected: 1,
}

@packet {
    len: VarInt,
    id: u8,
    event: Event(id),
}

ClientVersion {
    major: u16,
    minor: u16,
}

Mode : Enum(u8) {
    Viewer: 0,
    Admin: 1,
}

HandshakeEvent : In(0) State(Handshake) {
    version: ClientVersion,
    mode: Mode,
    username: Array(16, u8)
    password: VarArray(VarInt, u8)
}
```

# Example Program

```zig
const std = @import("std");
const zb = @import("zeebuffer.zig"); // Include generated file

fn handshake(ctx: ?*anyopaque, event: *zb.InHandshakeEventHandshake) anyerror!void {

}

pub fn main() !void {
    const allocator = // ...
    var reader = // Anything with an AnyReader interface
    var writer = // Anything with an AnyWriter interface

    var pid: u32 = 1337; // Some data that needs to be shared

    var proto = zb.Protocol.init(.{
        .HandshakeEvent_handler = &handshake,
    }, reader, writer);
    proto.user_context = &pid;

    while(true) {
        try proto.poll(allocator);
    }
}

```

# ¿Parker Jones?

Thank you for helping design the protocol!