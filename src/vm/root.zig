pub const bytecode = @import("bytecode.zig");
pub const ChannelID = @import("VM.zig").ChannelID;
pub const ConstantID = @import("VM.zig").ConstantID;
pub const disasm = @import("disasm.zig");
pub const dispatch = @import("dispatch.zig");
pub const errors = @import("errors.zig");
pub const RunError = @import("errors.zig").RunError;
pub const RunErrorKind = @import("errors.zig").RunErrorKind;
pub const RunFailure = @import("errors.zig").RunFailure;
pub const RunResult = @import("errors.zig").RunResult;
pub const callable = @import("callable.zig");
pub const GlobalID = @import("VM.zig").GlobalID;
pub const interner = @import("interner.zig");
pub const lookup = @import("lookup.zig");
pub const memory = @import("memory.zig");
pub const Value = memory.Value;
pub const opcode = @import("opcode.zig");
pub const run = @import("run.zig");
pub const Instruction = opcode.Instruction;
pub const Opcode = opcode.Opcode;
pub const perf = @import("perf.zig");
pub const print = @import("print.zig");
pub const ProgramCounter = @import("VM.zig").ProgramCounter;
pub const CoreAtoms = @import("CoreAtoms.zig").CoreAtoms;
pub const isFalse = @import("memory.zig").isFalse;
pub const Scheduler = @import("scheduler.zig").Scheduler;
pub const table = @import("table.zig");
pub const tests = @import("tests.zig");
pub const VM = @import("VM.zig").VM;

// re-exports from root module (source of truth)
// note: also available as revo.CoreAtoms and revo.isFalse
// root module is revo
test {
    _ = @import("bytecode.zig");
    _ = @import("VM.zig");
    _ = @import("errors.zig");
    _ = @import("callable.zig");
    _ = @import("interner.zig");
    _ = @import("memory.zig");
    _ = @import("run.zig");
    _ = @import("opcode.zig");
    _ = @import("perf.zig");
    _ = @import("table.zig");
    _ = @import("tests.zig");
}
