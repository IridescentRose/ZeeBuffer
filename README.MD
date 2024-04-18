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
# This is a comment

# Specify the target endianness
@endian big

# Specify the protocol's perspective
@direction in

# Define the valid connection states
# 0 is the default state
@state {
    Handshake: 0,
    Connected: 1,
}

# Packet defines the data being input
# Packets start with a length field or an id field
# Length-preceeded packets are read into a buffer
# The buffer is bounds checked while intepretting
# ID-based packets are read in single-shot
@packet {
    len: VarInt,
    id: u8,

    # This is the event dispatcher, which uses ID to switch upon the defined packets
    event: Event(id),
}

# This is plain ol' data.
ClientVersion {
    major: u16,
    minor: u16,
}

# This is an enum
# It has an integral backing type of fixed length
Mode : Enum(u8) {
    Viewer: 0,
    Admin: 1,
}

# This is an input event, when read this is dispatched
# The In(), Out(), or InOut() attributes determine the accepted directions of a packet
# Events with the same name are permitted if their input and output attributes differ
# The argument to the attributes is the ID number of the packet
# The State() attribute determines if this packet is valid for the state.
# Packets may have overlapping ID numbers if in different states
# If State() is not present, the packet applies in all states
HandshakeEvent : In(0) State(Handshake) {
    version: ClientVersion,
    mode: Mode,
    username: Array(16, u8) # Arrays are specified by length, then type -- any type including user types are valid
    password: VarArray(VarInt, u8) # VarArrays are specified by the integral length, then the same type rules apply
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