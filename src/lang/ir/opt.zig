//! one driver for the three ir passes, same order as always
//!   fold leaves dead constants, dce reclaims em, peephole tidies moves + jumps
//!   passes stay coupled by the fold-then-dce invariant, this just names it

const Compiler = @import("../compiler/root.zig").Compiler;
const dce = @import("dce.zig");
const fold = @import("fold.zig");
const peephole = @import("peephole.zig");

/// run all three ir passes in pipeline order, bit-identical to separate calls
pub fn optimize(self: *Compiler) !void {
    try fold.foldIr(self);
    try dce.dceIr(self);
    try peephole.peepholeIr(self);
}
