const std = @import("std");

pub const Index = u16;
pub const Endian = enum { little, big };

pub const AttributeKind = enum(u16) {
    Enum,
    Event,
};

pub const Attribute = struct {
    kind: AttributeKind,
    values: []Index,
};

pub const Field = struct {
    name: Index,
    values: []Index,
};

pub const Entry = struct {
    name: Index,
    is_state: bool = false,
    attribute: ?Attribute = null,
    fields: []Field,
};

endian: Endian = .little,
entries: []Entry,
