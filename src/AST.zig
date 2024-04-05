const std = @import("std");

pub const Index = u16;

pub const AttributeType = enum(u16) {
    Enum,
    InEvent,
    OutEvent,
    InOutEvent,
    Compressed,
    Encrypted,
    State,
};

pub const Attribute = struct {
    type: AttributeType,
    value: Index,
};

pub const Field = struct {
    name: Index,
    kind: Index,
    len_kind: u32 = 0,
};

pub const Special = enum {
    None,
    State,
    Packet,
};

pub const Entry = struct {
    name: Index,
    special: Special = .None,
    attributes: ?[]Attribute = null,
    fields: []Field,
};

pub const Endian = enum {
    Little,
    Big,
};

pub const Direction = enum {
    In,
    Out,
};

endian: Endian = .Little,
direction: Direction = .In,
entries: []Entry,
