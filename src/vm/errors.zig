const std = @import("std");

const revo = @import("revo");
const diagnostic = revo.lang.diagnostic;
pub const TraceFrame = diagnostic.TraceFrame;

pub const RunError = error{
    StackUnderflow,
    KeyDNE,
    StackOverflow,
    InvalidConstant,
    InvalidLocal,
    ConstantReassignment,
    WrongArity,
    TypeError,
    IncompatibleTypes,
    DivisionByZero,
    UndefinedVariable,
    NotAFunction,
    FrameUnderflow,
    PickedFromVoid,
    FunctionDNE,
    ProgramEnd,
    Panic,
    AssertionFailed,
    OutOfMemory,
    mystery,
    ModuleNotFound,
    IoError,
    CyclicImport,
    ImportFailed,
    InvalidChannel,
    Parked,
    InvalidBytecode,
};

pub const RunErrorKind = enum {
    StackUnderflow,
    StackOverflow,
    InvalidConstant,
    InvalidLocal,
    TypeError,
    IncompatibleTypes,
    DivisionByZero,
    ShiftAmountOutOfRange,
    UndefinedVariable,
    NotAFunction,
    WrongArity,
    FrameUnderflow,
    PickedFromVoid,
    FunctionDNE,
    KeyDNE,
    Panic,
    OutOfMemory,
    ConstantReassignment,
    ProgramEnd,
    AssertionFailed,
    ModuleNotFound,
    IoError,
    CyclicImport,
    ImportFailed,
    InvalidChannel,
    Parked,
    InvalidBytecode,
    mystery,

    // it would be really cool if i could do this at comptime
    pub fn message(self: RunErrorKind) []const u8 {
        return switch (self) {
            .StackUnderflow => "stack underflow!",
            .StackOverflow => "stack overflow!",
            .InvalidConstant => "invalid constant!",
            .InvalidLocal => "invalid local!",
            .TypeError => "type error!",
            .IncompatibleTypes => "incompatible types!",
            .DivisionByZero => "division by zero!",
            .ShiftAmountOutOfRange => "shift amount out of range!",
            .UndefinedVariable => "undefined variable!",
            .NotAFunction => "value is not a function!",
            .WrongArity => "wrong arity!",
            .FrameUnderflow => "frame underflow!",
            .PickedFromVoid => "picked from void!",
            .FunctionDNE => "function dne!",
            .Panic => "panic!!",
            .KeyDNE => "key does not exist!",
            .OutOfMemory => "out of memory!",
            .ConstantReassignment => "reassignment to constant!",
            .ProgramEnd => "program end!",
            .AssertionFailed => "assertion failed!",
            .ModuleNotFound => "module not found!",
            .IoError => "io error!",
            .CyclicImport => "cyclic import!",
            .ImportFailed => "import failed!",
            .InvalidChannel => "invalid channel!",
            .Parked => "fiber parked!",
            .InvalidBytecode => "invalid bytecode!",
            .mystery => "mystery!",
        };
    }
};

pub const RunFailure = struct {
    pub const max_trace_frames = 64;

    kind: RunErrorKind,
    report: diagnostic.Report,
    part_len: usize = 0,
    parts: [max_trace_frames + 2]diagnostic.Part = @splat(diagnostic.Part{ .@"error" = "" }),
    trace_len: usize = 0,
    trace: [max_trace_frames]TraceFrame = @splat(TraceFrame.empty()),

    pub fn render(self: RunFailure, alloc: std.mem.Allocator, writer: *std.Io.Writer, source: []const u8) !void {
        return self.renderAt(
            alloc,
            writer,
            self.report.source_name orelse "<source>",
            self.report.source orelse source,
        );
    }

    pub fn renderAt(
        self: RunFailure,
        alloc: std.mem.Allocator,
        writer: *std.Io.Writer,
        source_name: []const u8,
        source: []const u8,
    ) !void {
        var report = self.report;
        report.source_name = source_name;
        report.source = source;
        report.parts = self.parts[0..self.part_len];
        try diagnostic.renderReport(alloc, writer, report);
    }
};

pub const RunResult = union(enum) {
    ok,
    err: RunFailure,
};

test "failure rendering includes stack trace frames" {
    var failure = RunFailure{
        .kind = .TypeError,
        .report = .{
            .source_name = "file.rv",
            .source = "ignored",
            .parts = &.{
                diagnostic.Part{ .@"error" = "boom" },
                .{ .span = .{ .span = .{ .line = 2, .column = 4, .start = 0, .end = 1 }, .role = .primary } },
            },
        },
        .part_len = 2,
        .trace_len = 2,
    };
    failure.parts[0] = diagnostic.Part{ .@"error" = "boom" };
    failure.parts[1] = .{ .span = .{ .span = .{ .line = 2, .column = 4, .start = 0, .end = 1 }, .role = .primary } };
    failure.parts[2] = .{ .trace = .{
        .function_name = "inner",
        .source_name = "file.rv",
        .span = .{
            .line = 2,
            .column = 4,
            .start = 0,
            .end = 1,
        },
    } };
    failure.parts[3] = .{ .trace = .{
        .function_name = "<module>",
        .source_name = "file.rv",
        .pc = 7,
    } };
    failure.part_len = 4;

    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();
    try failure.render(std.testing.allocator, &buf.writer, "unused");

    try std.testing.expect(std.mem.find(u8, buf.written(), "stack trace:") != null);
    try std.testing.expect(std.mem.find(u8, buf.written(), "0: inner at file.rv:2:4") != null);
    try std.testing.expect(std.mem.find(u8, buf.written(), "1: <module> at file.rv:pc=7") != null);
}
