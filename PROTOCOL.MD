# Protocol Specification

I want to write a schema to describe a protocol, from the packet layout and features, to the data contained. 

Packet Layout:
```zb
@endian big

# Base Packet
@packet {
    len: varInt,
    data: protoData,
}

# Packet in compressed mode
@packet : Compressed(gzip) {
    len: varInt,
    uncompLen: varInt,
    data: protoData,
}

# Packet in compressed and encrypted mode
@packet : Compressed(gzip), Encrypted(aes256) {
    len: varInt,
    uncompLen: varInt,
    data: protoData, # Decompress then Decrypt
}

```

The receiver then defines the property (language specific) to change into the various toggled modes (list enabled in order)

The other schema should define the data structures contained within the protocol:

```zb
@endian big

# ...

# This is just regular data
vec3 {
    x: f64,
    y: f64,
    z: f64,
}

# This is an enum with backing type
weatherType : Enum(u8) {
    Sunny: 1,
    Cloudy: 2,
    Rainy: 3,
}

# This is an event with ID 1
# This packet only works in the play state
playerPositionUpdate : InOut(1) State(Play) {
    id: u32,
    pos: vec3,
}

# This is an event with ID 2
# This packet only works in the play state
environmentTick : In(2) State(Play) {
    time: u64,
    weather: weatherType,
}

# This is an event with ID 1
# The conflict with the playerPositionUpdate event is resolved by
# the state of the packet, since this packet is in the handshake state
# and the playerPositionUpdate packet is in the play state
# This packet only works in the handshake state
handshake: Out(1) State(Handshake) {
    protocolVersion: varInt,
    serverAddress: string,
    serverPort: u16,
    nextState: u8,
}
```

## Defining the direction of the buffers

```
@direction in
```

This means that when the `In()` event specifier this it the input, and the `Out()` event specifier means that this is the output. If the direction is swapped, the `In()` is treated as output and `Out()` is treated as input. This could also be called as the relative direction of the protocol (relative to server / client).

## Defining custom connection state

```
@state {
	Handshake: 0,
	Status: 1,
	Login: 2,
	Play: 3
}
```

This defines the enum to be used in the `State()` specifier, which results in the data parsed being reflected on a multi-match statement. If `@state` is specified and an event does not have a `State()` specifier, then it is treated as the same across states.