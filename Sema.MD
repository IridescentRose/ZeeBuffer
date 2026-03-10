# ZeeBuffer Semantic Validation Rules

Rules enforced by `sema.verify()` on a lowered `IR.Program`. Rules that are
already enforced structurally by the type system or caught during lowering are
noted but not re-checked here.

---

## Protocol

No rules. The lowerer's typed `Protocol` struct encodes all constraints —
`endian` is an `IR.Endian` enum and `version` is a `u32`, so invalid values
cannot survive lowering.

---

## States

| Rule | Error |
|---|---|
| At least one state must be declared | `EmptyStatesBlock` |

Duplicate state names are caught during lowering (pass 1 name table insertion)
and are not re-checked here.

---

## Enums

| Rule | Error |
|---|---|
| Backing type must be `u8`, `u16`, `u32`, or `u64` | `InvalidEnumBackingType` |
| At least one variant must be declared | `EmptyEnum` |
| No duplicate variant names within the same enum | `DuplicateVariantName` |
| No duplicate variant values within the same enum | `DuplicateVariantValue` |

---

## Structs

| Rule | Error |
|---|---|
| At least one field must be declared | `EmptyStruct` |
| No duplicate field names within the same struct | `DuplicateFieldName` |
| `varint` may not appear as a standalone field type | `VarintNotAllowedAsFieldType` |

---

## Packets

| Rule | Error |
|---|---|
| No duplicate field names within the same packet | `DuplicateFieldName` |
| `varint` may not appear as a standalone field type | `VarintNotAllowedAsFieldType` |
| No two packets may share the same ID within the same `state + direction` pair | `DuplicatePacketID` |

Packet `state` and `direction` cannot be invalid — they are resolved to typed
IR values during lowering and cannot represent unknown states or directions.

Note on `DuplicatePacketID`: two packets may share an ID if they differ in
state or direction. For example, `Handshake[0x00] -> Client` and
`Handshake[0x00] -> Server` is valid. `Handshake[0x00] -> Client` appearing
twice is not.

---

## Arrays

| Rule | Error |
|---|---|
| Prefix type must be `u8`, `u16`, `u32`, or `varint` | `InvalidArrayPrefixType` |
| Fixed size must be greater than zero | `ZeroLengthArray` |
| Element type may not be `varint` | `VarintNotAllowedAsElementType` |
| Element type may not be `bool` | `BoolNotAllowedAsElementType` |

---

## Program-level

| Rule | Error |
|---|---|
| Enum and struct names must be unique across both namespaces | `DuplicateTypeName` |

Enums and structs share a single type namespace. A `struct Foo` and an
`enum Foo` in the same file is ambiguous for any consumer of the generated
code and is always an error.

---

## What sema does not check

The following are intentionally left to the protocol designer. ZeeBuffer does
not enforce them:

- Whether a `-> Both` packet makes semantic sense for the protocol
- Whether enum variant values are contiguous or start at zero
- Whether the protocol `version` field matches any external contract
- Field ordering within packets or structs
- Whether declared states are actually used by any packet
