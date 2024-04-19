# Protocol Specification


## Comments

Comments begin with `#` and last until the end of the line
Comments can be placed anywhere in the line
```
# This is a comment
```

## Endianness

The endianness is always the network-observed endianness. If conversion is required, this happens on either side of the connection. The only valid endianness schemes are `big` and `little`. If none is provided `little` is selected and a warning is raised.

```
@endian big
```

## Direction

The direction tag represents the perspective of the connection. In the input direction, all events attributed as input will be generated in the polling code as the valid readable events. If the direction is set to output, then all events attributed as output will be generated in the pollinig code as the valid readable events. The same goes for the writing code.

The valid directions are `in` and `out`. If none is provided `in` is selected and a warning is raised.

```
@direction in
```

## States

The `@state` directive indicates a special structure, in this case the state enumeration. The `@state` directive must be supplied only once in the protocol specification. The following states will then be valid entries as arguments to the state attribute for events.

The enumeration cannot be used as a data type for other structures. The default starting state is `0`

```
@state {
    Handshake: 0,
    Connected: 1,
}
```

## Packet

The `@packet` directive indicates a special structure. The `@packet` directive must be supplied once without attributes, but can be redefined with attributes.

Packet defines the input data and how to parse it. They either start with the `len` field or an `id` field.
`len`-preceeded packets are read into a buffer and is bounds checked during interpretting and polling packets.
`id`-based packets are read in a single pass according to the data definitions.

```
@packet {
    len: VarInt,
    id: u8,
    event: Event(id),
}
```

## Data

Regular data structures are defined with an identifier name followed by `{` and ended with `}`. Each field is specified in well-defined order (top-down) with a respective backing type. 

```
ClientVersion {
    major: u16,
    minor: u16,
}
```

The valid existing types are `VarInt`, `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`, `f32`, `f64`, and `bool`

User-defined data types can also be used, such as these Structs, and Enums.

## Enum

Enums are defined with the `Enum` attribute. The attribute has a single argument which is the backing type of the enumeration. This must be a fixed-size integral type. The fields of an enum are mapped to integer values. These integers can be specified as hex via `0x` or octal via `0o`.

```
Mode : Enum(u8) {
    Viewer: 0,
    Admin: 1,
}
```

## Events

Events are specified by having the `In`, `Out` or `InOut` attribute. These are mutually exclusive. The argument of these attributes is a number representing the packet ID number.

Events are valid within a specific `State` attribute. If no `State` is present, it is in all states. 

Events with the same ID and Name are permitted if they differ by `State` or the `In` and `Out` attributes.

```
HandshakeEvent : In(0) State(Handshake) {
    version: ClientVersion,
    mode: Mode,
    username: Array(16, u8) 
    password: VarArray(VarInt, u8) 
}
```

The Event dispatch attribute as seen in packet is used to call dispatch on the existing event structures as deemed by their directional attributes and state attribute. The argument to the dispatch is the name of the struct member which holds the ID.

```
@packet {
    id: u8,
    event: Event(id),
}
```

## Arrays

Arrays are an attribute type which has an integral length (hex and octal are valid here too) followed by the backing type. All base types and user-defined types are valid here except for State and Packet.

```
HandshakeEvent : In(0) State(Handshake) {
    username: Array(16, u8) 
}
```

### Variable Arrays

Sometimes arrays are packed with an unknown size, and must be parsed as a length-prepended or variable length array. This feature requires dynamic allocation. The first argument to the VarArray attribute is the integral type prepended, followed by the backing type, which follows the same rules as above.

```
HandshakeEvent : In(0) State(Handshake) {
    password: VarArray(VarInt, u8) 
}
```
