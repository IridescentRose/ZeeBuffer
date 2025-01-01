const CCodegen = @import("emitters/CCodegen.zig");
const ZigCodegen = @import("emitters/ZigCodegen.zig");
const IR = @import("../IR.zig");

pub const TargetLanguage = enum {
    Zig,
    C,
};

pub fn generate_code(ir: *const IR, filename: []const u8, target: TargetLanguage) !void {
    switch (target) {
        .Zig => {
            var codegen = ZigCodegen.init(ir);
            try codegen.generate_code(filename);
        },
        .C => {
            var codegen = CCodegen.init(ir);
            try codegen.generate_code(filename);
        },
    }
}
