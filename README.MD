# ZeeBuffer

A DSL for defining binary network protocols — designed for correctness, clarity, and zero-copy implementation. Built in Zig.

---

## What is ZeeBuffer?

ZeeBuffer is a schema language for describing binary wire protocols. You define the structure of your messages once, and ZeeBuffer handles code generation for serialization, deserialization, and documentation across multiple target languages.

It is built around a small set of first-class concepts: a protocol configuration block, connection states, enums, structs, and packets. There is no runtime, no reflection, and no hidden allocation — the schema is a complete, unambiguous description of every byte on the wire.

---

## Why ZeeBuffer?

### Zero-copy by design

ZeeBuffer's type system is designed to enable zero-copy parsing wherever possible. Because every field has a statically known size or an explicit length prefix, a conforming implementation can map packet fields directly onto a received buffer — no intermediate allocation required. Translations that are unavoidable (endian swaps, varint decoding) are made explicit by the schema rather than hidden inside a runtime.

Zig is a natural fit for this goal. Its comptime evaluation, explicit allocator model, and lack of hidden control flow mean that ZeeBuffer's generated code can make the same guarantees the schema does: no surprise allocations, no implicit copies, no runtime library to link against.

### Explicit over implicit

Every decision that affects the wire format is visible in the schema. Endianness is declared at the protocol level. Array lengths are always stated — either as a fixed constant or a concrete prefix type (`u8`, `u16`, `u32`, or `varint`). Packet IDs are hex literals on the packet declaration itself. Nothing is inferred, defaulted silently, or resolved through inheritance.

### State-aware packet routing

Protocols that use connection phases — handshake, login, play, and so on — can declare those states explicitly. Each packet is bound to a specific state and direction, so a generated parser can statically reject packets that are invalid for the current connection phase without any runtime configuration.

### Reusable struct types

Structs are first-class types. A `Vec3`, a `PlayerMetadata`, or any other composite value can be defined once and referenced as a field type, embedded inside other structs, or used as the element type of a length-prefixed array. There is no duplication and no copy implied by embedding — a struct reference in ZeeBuffer means the fields are laid out inline at that position in the packet.

### Multi-language code generation

ZeeBuffer is a source of truth, not an implementation. A single `.zb` file generates serialization and deserialization code for every target language in your stack. Protocol changes are made in one place and propagated everywhere, eliminating the class of bugs that comes from hand-written parsers drifting out of sync with each other.

### Human-readable as documentation

ZeeBuffer files are intended to be readable by engineers who have never used the toolchain. The syntax is close enough to common type system notation that a `.zb` file doubles as protocol documentation — reviewable in a pull request, diffable over time, and greppable by packet name or field.

---

## Core Concepts

ZeeBuffer schemas are written in `.zb` files.

### Protocol block

The `protocol` block declares global wire format settings. Every file has exactly one.

```
protocol MyProtocol {
    endian: big,
    version: 1,
}
```

### States

States model the phases of a connection lifecycle. Each packet is bound to exactly one state.

```
states {
    Handshake = 0,
    Login     = 1,
    Play      = 2,
}
```

### Enums

Enums are backed by a concrete integer type and occupy exactly that many bytes on the wire. They are used as field types in structs and packets.

```
enum WeatherType : u8 {
    Sunny  = 1,
    Cloudy = 2,
    Rainy  = 3,
}
```

### Structs

Structs are composite types that are always fully sized. Every field must have a deterministic wire size, either through a fixed-size type or an explicit length prefix. Structs can be nested and used as array element types.

```
struct Vec3 {
    x: f64,
    y: f64,
    z: f64,
}
```

### Packets

Packets are the top-level messages sent over the wire. Each packet declares its state, its wire ID, and its direction. The direction is `Client` (server sends), `Server` (client sends), or `Both`.

```
packet MovementCommand : Play[0x07] -> Server {
    entityId: u32,
    newPos:   Vec3,
}
```

### Array types

All arrays must declare their size strategy. There are no unsized arrays — every array is either fixed-length or carries an explicit length prefix on the wire.

| Syntax          | Meaning                              |
|-----------------|--------------------------------------|
| `[u8; 32]`      | Fixed: exactly 32 bytes              |
| `[u8; u8]`      | Length-prefixed by a `u8` count      |
| `[u8; u16]`     | Length-prefixed by a `u16` count     |
| `[u8; u32]`     | Length-prefixed by a `u32` count     |
| `[u8; varint]`  | Length-prefixed by a varint count    |

The element type can be any primitive, enum, or struct.

---

## Primitive Types

| Type             | Size     | Description              |
|------------------|----------|--------------------------|
| `u8`–`u64`       | 1–8 bytes | Unsigned integers        |
| `i8`–`i64`       | 1–8 bytes | Signed integers          |
| `f32`, `f64`     | 4, 8 bytes | IEEE 754 floats         |
| `bool`           | 1 byte   | Boolean                  |
| `varint`         | 1–5 bytes | Variable-length integer  |

---

## Use Cases

ZeeBuffer is a good fit for any project where you own both ends of a binary protocol and want a single authoritative source of truth for the wire format. Typical use cases include:

- **Game networking** — stateful client/server protocols with distinct connection phases and high message throughput, where zero-copy parsing is a performance requirement
- **Embedded and IoT** — constrained environments where allocation is expensive or forbidden, and the wire format must be auditable without running code
- **Internal services** — high-performance RPC between services in the same stack, where Protobuf or similar tools introduce more overhead or abstraction than is useful
- **Protocol documentation** — teams that want a machine-readable, diffable specification that can be reviewed alongside the implementation

---

## Comparison with Similar Tools

| | ZeeBuffer | Protobuf | Cap'n Proto | Kaitai Struct |
|---|---|---|---|---|
| Zero-copy target | ✓ | Partial | ✓ | ✗ |
| State-aware routing | ✓ | ✗ | ✗ | ✗ |
| Explicit wire IDs | ✓ | ✗ | ✗ | ✓ |
| Multi-language codegen | ✓ | ✓ | ✓ | ✓ |
| No schema evolution overhead | ✓ | ✗ | ✗ | ✓ |
| Human-readable as docs | ✓ | Partial | Partial | ✓ |

ZeeBuffer makes different tradeoffs than Protobuf or Cap'n Proto: it does not support schema evolution or optional fields, because its target is protocols where both sides are deployed together and the wire format is fully controlled. In exchange, it produces simpler, leaner generated code with no runtime library dependency.

---

## Current Status

Currently the compiler is written in Zig and only outputs to Zig. C support is planned but not yet implemented.

The compiler is in development and not yet ready for use.
