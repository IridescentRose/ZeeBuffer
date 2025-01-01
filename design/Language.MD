# Design Document

## Introduction

ZeeBuffers is a protocol specification language for binary data serialization and deserialization. The format operates on
the assumption of an input packet, state, direction, and packet type. The format is designed to be simple and efficient
while providing a high degree of flexibility and performance. The format is designed to be *mostly* zero-copy, with the
exception being that integers are read and written in a byte-order specific manner (little-endian or big-endian). Other data
buffers are merely pointers to the original data buffer.

### Revisions of ZeeBuffers 0.0

Intially, ZeeBuffers 1 attempted to increase the scope to include the parsing of packets from a raw stream itself. This
however lent itself to a more complex design and was ultimately abandoned in favor of a simpler design that focused on
simply doing the data serialization and deserialization, while still providing the ability to be used in "packet route"
style systems like `express` or `koa`.

This means that a user of ZeeBuffers will have to handle the reading and writing of the initial packet themselves, and
then pass the data to the ZeeBuffers library for serialization and deserialization. This is a downgrade in some respects,
but it also allows for a simpler and more efficient design for the core library.

## Specification

```
# Set the byte order to big endian. This can be overriden per field, but this is the default.
# This can only be set once per file.
@endian big


# Define the valid connection states. This can be used to restrict the packets that can be sent or received
# based on the current state of the connection.
# This can only be set once per file.
@state {
    Handshake: 0,
    Login: 1,
    Status: 2,
    Play: 3,
}

# Regular Data
vec3 {
    x: f64,
    y: f64,
    z: f64,
}

# Enum with a u8 backing type
weatherType : Enum(u8) {
    Sunny: 1,
    Cloudy: 2,
    Rainy: 3,
}

# Enums can be used in struct attributes
handshakeEventType : Enum(u8) {
    Hello: 0,
    Transition: 1,
}

# Define an event that can be sent from the client to the server
# The Event attribute specifies the event ID number, the state it can be sent in, and the direction.
# The event ID number must be unique within the target state.
# The state must be a valid state defined in the @state block.
handshake: Event(Hello, Handshake, Client) {
    protocolVersion: u32,
    username: Array(u8, 16),
    key: Array(u8, 32),
}

# Define a event that can be sent from the server to the client
# To send to both the client and the server, use the Both direction.
# It is valid to have multiple events with the same ID number, as long as they are in different states and/or directions.
# This is also valid for the event name itself.
handshake: Event(Hello, Handshake, Server) {
    protocolVersion: u32,
    serverAddress: Array(u8, 16),
    serverPort: u16,
}

# Define a transition event that can be sent from the client to the server and vice versa.
# This event can be sent in the Handshake state, and the desired state is the state that the client or server
# wants to transition to.
transition: Event(Transition, Handshake, Both) {
    desiredState: u8,
}
```
