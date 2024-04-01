const std = @import("std");

const StrType = enum(u8) {
    State = 0, // State is a reserved enumeration
    Enum = 1, // This is a global enumeration
    Literal = 2, // This is an integer literal
    UserType = 3, // This is a user-defined type
    BaseType = 4, // This is a base type
};

const BaseType = enum(u32) {
    U8 = 0,
    U16 = 1,
    U32 = 2,
    U64 = 3,
    I8 = 4,
    I16 = 5,
    I32 = 6,
    I64 = 7,
    F32 = 8,
    F64 = 9,
    Bool = 10,
    VarInt = 11,
};

const StrEntry = struct {
    name: []const u8,
    type: StrType,
    value: u32 = 0, // TODO: Make this something more generic
};

const StrTable = struct {
    entries: std.ArrayList(StrEntry),
};
