const std = @import("std");
const alloc = std.testing.allocator;
const io = std.testing.io;

const diagnostic = @import("diagnostic.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const pipeline = @import("pipeline.zig");
const revo = @import("revo");

pub fn runtime() revo.Runtime {
    return .{
        .alloc = alloc,
        .io = io,
        .diag_alloc = alloc,
        .diag_arena = null,
    };
}

pub fn expectPrinted(source: []const u8, expected: []const u8) !void {
    try Parser.testing.expectPrinted(source, expected);
}

pub fn expectTypes(source: []const u8, expected: []const Lexer.TokenType) !void {
    try Lexer.testing.expectTypes(source, expected);
}

pub fn expectTokens(source: []const u8, expected: []const Lexer.testing.ExpectedToken) !void {
    try Lexer.testing.expectTokens(source, expected);
}

const TopResult = struct {
    vm: revo.VM,
    value: revo.Data,

    pub fn deinit(self: *TopResult) void {
        self.vm.deinit();
    }
};

fn compileChecked(vm: *revo.VM, source: []const u8) ![]revo.Instruction {
    const result = try pipeline.build(vm, .{ .text = source }, .{
        .install_debug_info = true,
    });
    return switch (result) {
        .ok => |artifact| blk: {
            alloc.free(artifact.spans);
            break :blk artifact.instructions;
        },
        .err => |lang_err| {
            revo.printBuildError(alloc, .{ .text = source }, lang_err);
            vm.runtime.resetDiagArena();
            return error.LangFailure;
        },
    };
}

fn runTopModuleChecked(vm: *revo.VM, source: []const u8, source_name: []const u8) !void {
    const result = try revo.module.runModule(vm, source_name, source, false);
    switch (result) {
        .ok => {},
        .err => |failure| {
            revo.printEvalError(alloc, source, failure);
            vm.runtime.resetDiagArena();
            return error.RuntimeFailure;
        },
    }
}

pub fn topResult(source: []const u8, module_dir: ?[]const u8) !TopResult {
    var vm = try revo.VM.init(runtime());
    errdefer vm.deinit();
    const src_name: []const u8 = if (module_dir) |dir| blk: {
        vm.module_dir = dir;
        const joined = try std.Io.Dir.path.join(alloc, &.{ dir, "<source>" });
        break :blk joined;
    } else "<source>";
    defer if (module_dir != null) alloc.free(src_name);
    try runTopModuleChecked(&vm, source, src_name);
    return .{
        .vm = vm,
        .value = vm.mainResult(),
    };
}

fn expectTopNumber(result: *TopResult, expected: f64) !void {
    const actual = result.value.asNumber() catch {
        std.debug.print("result was not a number, it was {s}\n", .{revo.std_lib.typeof(result.value, &result.vm)});
        return error.TypeMismatch;
    };
    if (@abs(expected - actual) > 0.000000001) {
        std.debug.print("wanted {}, got {}\n", .{ expected, actual });
        return error.NumbersDontMatch;
    }
}

fn expectTopAtom(result: *TopResult, expected: []const u8) !void {
    const s = result.value.asAtom() orelse {
        std.debug.print("result was not a atom, it was {s}\n", .{revo.std_lib.typeof(result.value, &result.vm)});
        return error.TypeMismatch;
    };
    std.testing.expectEqualStrings(expected, result.vm.stringValue(s)) catch {
        std.debug.print("wanted :{s}, got :{s}\n", .{ expected, result.vm.stringValue(s) });
        return error.AtomsDontMatch;
    };
}

fn expectTopString(result: *TopResult, expected: []const u8) !void {
    try std.testing.expect(result.value.isString());
    try std.testing.expectEqualStrings(expected, result.vm.stringValue(result.value.asString().?));
}

fn expectTopTypeValue(result: *TopResult, expected: revo.memory.Type) !void {
    try std.testing.expect(result.value.tag() == expected);
}

pub fn topNumber(source: []const u8, expected: f64) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try expectTopNumber(&result, expected);
}

pub fn topNumberInDir(module_dir: []const u8, source: []const u8, expected: f64) !void {
    var result = try topResult(source, module_dir);
    defer result.deinit();
    try expectTopNumber(&result, expected);
}

pub fn topAtom(source: []const u8, expected: []const u8) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try expectTopAtom(&result, expected);
}

pub fn topString(source: []const u8, expected: []const u8) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try expectTopString(&result, expected);
}

pub fn topStringInDir(module_dir: []const u8, source: []const u8, expected: []const u8) !void {
    var result = try topResult(source, module_dir);
    defer result.deinit();
    try expectTopString(&result, expected);
}

pub fn topType(source: []const u8, expected: revo.memory.Type) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try expectTopTypeValue(&result, expected);
}

pub fn topNil(source: []const u8) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try std.testing.expectEqual(revo.Data.new.nil(), result.value);
}

pub fn topTrue(source: []const u8) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try std.testing.expect(!revo.isFalse(result.value));
}

pub fn topFalse(source: []const u8) !void {
    var result = try topResult(source, null);
    defer result.deinit();
    try std.testing.expect(revo.isFalse(result.value));
}

fn buildOkWithWarnings(source: []const u8, vm: *revo.VM, w: *?diagnostic.Report) !void {
    const result = try pipeline.buildWithWarnings(vm, .{ .text = source }, .{
        .install_debug_info = false,
    }, w);
    switch (result) {
        .ok => |artifact| {
            defer alloc.free(artifact.instructions);
            defer alloc.free(artifact.spans);
        },
        .err => |lang_err| {
            revo.printBuildError(alloc, .{ .text = source }, lang_err);
            vm.runtime.resetDiagArena();
            return error.ExpectedCompileSuccess;
        },
    }
}

pub const TmpMod = struct {
    tmp: std.testing.TmpDir,
    dir: [:0]const u8,

    pub fn init(files: []const struct { path: []const u8, data: []const u8 }) !TmpMod {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        for (files) |f| try tmp.dir.writeFile(io, .{ .sub_path = f.path, .data = f.data });
        const dir = try tmp.dir.realPathFileAlloc(io, ".", alloc);
        return .{ .tmp = tmp, .dir = dir };
    }

    pub fn deinit(self: *TmpMod) void {
        alloc.free(self.dir);
        self.tmp.cleanup();
    }
};

pub fn expectWarning(source: []const u8, snippet: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    var w: ?diagnostic.Report = null;
    defer if (w) |*wr| wr.deinit(alloc);
    try buildOkWithWarnings(source, &vm, &w);
    const wr = w orelse return error.ExpectedWarning;
    const msg = diagnostic.firstWarn(wr) orelse return error.ExpectedWarning;
    try std.testing.expect(std.mem.find(u8, msg, snippet) != null);
}

pub fn expectWarningCode(source: []const u8, code: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    var w: ?diagnostic.Report = null;
    defer if (w) |*wr| wr.deinit(alloc);
    try buildOkWithWarnings(source, &vm, &w);
    const wr = w orelse return error.ExpectedWarning;
    const got = wr.code orelse return error.ExpectedCode;
    try std.testing.expectEqualStrings(code, got);
}

pub fn expectSuggestion(source: []const u8, snippet: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    var w: ?diagnostic.Report = null;
    defer if (w) |*wr| wr.deinit(alloc);
    try buildOkWithWarnings(source, &vm, &w);
    const wr = w orelse return error.ExpectedWarning;
    for (wr.parts) |part| {
        if (part == .suggestion and std.mem.find(u8, part.suggestion.replacement, snippet) != null) return;
    }
    return error.ExpectedSuggestion;
}

pub fn expectNoWarning(source: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    var w: ?diagnostic.Report = null;
    defer if (w) |*wr| wr.deinit(alloc);
    try buildOkWithWarnings(source, &vm, &w);
    try std.testing.expect(w == null);
}

fn buildExpectingFailure(source: []const u8, vm: *revo.VM) !pipeline.Error {
    const result = try pipeline.build(vm, .{ .text = source }, .{
        .install_debug_info = false,
    });
    switch (result) {
        .ok => |artifact| {
            defer alloc.free(artifact.instructions);
            defer alloc.free(artifact.spans);
            return error.ExpectedCompileFailure;
        },
        .err => |failure| return failure,
    }
}

pub fn expectErrorCode(source: []const u8, code: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const err = try buildExpectingFailure(source, &vm);
    defer vm.runtime.resetDiagArena();
    const got = switch (err) {
        inline else => |f| f.report.code orelse return error.ExpectedCode,
    };
    try std.testing.expectEqualStrings(code, got);
}

pub fn expectCompileError(source: []const u8, expected: pipeline.LowerErrorKind) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const err = try buildExpectingFailure(source, &vm);
    defer vm.runtime.resetDiagArena();
    switch (err) {
        .lower => |failure| try std.testing.expectEqual(expected, failure.kind),
        else => return error.ExpectedLowerFailure,
    }
}

/// semantic failures carry their own kind; this asserts the stage.
/// use expectSemanticFailure for line and message precision.
pub fn expectSemanticError(source: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const err = try buildExpectingFailure(source, &vm);
    defer vm.runtime.resetDiagArena();
    switch (err) {
        .semantic => {},
        else => return error.ExpectedSemanticFailure,
    }
}

pub fn expectCompileErrorInDir(module_dir: []const u8, source: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();
    vm.module_dir = module_dir;

    const source_name = try std.Io.Dir.path.join(alloc, &.{ module_dir, "<source>" });
    defer alloc.free(source_name);

    const result = try pipeline.build(&vm, .{ .name = source_name, .text = source }, .{
        .install_debug_info = false,
    });
    switch (result) {
        .ok => |artifact| {
            defer alloc.free(artifact.instructions);
            defer alloc.free(artifact.spans);
            return error.ExpectedCompileFailure;
        },
        .err => |failure| switch (failure) {
            .semantic, .lower => {
                vm.runtime.resetDiagArena();
            },
            .expand, .parse => {
                vm.runtime.resetDiagArena();
                return error.ExpectedCompileFailure;
            },
        },
    }
}

fn checkExpandError(vm: *revo.VM, result: pipeline.BuildResult, expected_message: []const u8) !void {
    switch (result) {
        .ok => |artifact| {
            defer vm.runtime.alloc.free(artifact.instructions);
            defer vm.runtime.alloc.free(artifact.spans);
            return error.ExpectedCompileFailure;
        },
        .err => |failure| switch (failure) {
            .expand => |diag| {
                const msg = diagnostic.firstError(diag.report).?;
                try std.testing.expectEqualStrings(expected_message, msg);
                vm.runtime.resetDiagArena();
            },
            else => return error.ExpectedExpandFailure,
        },
    }
}

pub fn expectExpandError(source: []const u8, expected_message: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const result = try pipeline.build(&vm, .{ .text = source }, .{
        .install_debug_info = false,
    });

    try checkExpandError(&vm, result, expected_message);
}

pub fn expectExpandErrorInDir(module_dir: []const u8, source: []const u8, expected_message: []const u8) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();
    vm.module_dir = module_dir;

    const source_name = try std.Io.Dir.path.join(alloc, &.{ module_dir, "<source>" });
    defer alloc.free(source_name);

    const result = try pipeline.build(&vm, .{ .name = source_name, .text = source }, .{
        .install_debug_info = false,
    });

    try checkExpandError(&vm, result, expected_message);
}

pub fn expectCompileFailure(
    source: []const u8,
    expected_kind: pipeline.LowerErrorKind,
    expected_line: u32,
    expected_column: u32,
    expected_message: []const u8,
) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const result = try pipeline.build(&vm, .{ .text = source }, .{
        .install_debug_info = false,
    });
    switch (result) {
        .ok => |artifact| {
            defer alloc.free(artifact.instructions);
            defer alloc.free(artifact.spans);
            return error.ExpectedCompileFailure;
        },
        .err => |failure| switch (failure) {
            .parse => return error.ExpectedLowerFailure,
            .expand => return error.ExpectedLowerFailure,
            .lower => |diag| {
                try std.testing.expectEqual(expected_kind, diag.kind);
                const span = diagnostic.primarySpan(diag.report).?;
                const msg = diagnostic.firstError(diag.report).?;
                try std.testing.expectEqual(expected_line, span.span.line);
                try std.testing.expectEqual(expected_column, span.span.column);
                try std.testing.expectEqualStrings(expected_message, msg);
                vm.runtime.resetDiagArena();
            },
            .semantic => return error.ExpectedLowerFailure,
        },
    }
}

pub fn expectSemanticFailure(
    source: []const u8,
    expected_line: u32,
    expected_column: u32,
    expected_message: []const u8,
) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const result = try pipeline.build(&vm, .{ .text = source }, .{
        .install_debug_info = false,
    });
    switch (result) {
        .ok => |artifact| {
            defer alloc.free(artifact.instructions);
            defer alloc.free(artifact.spans);
            return error.ExpectedCompileFailure;
        },
        .err => |failure| switch (failure) {
            .parse => return error.ExpectedSemanticFailure,
            .expand => return error.ExpectedSemanticFailure,
            .lower => return error.ExpectedSemanticFailure,
            .semantic => |diag| {
                const span = diagnostic.primarySpan(diag.report).?;
                const msg = diagnostic.firstError(diag.report).?;
                try std.testing.expectEqual(expected_line, span.span.line);
                try std.testing.expectEqual(expected_column, span.span.column);
                try std.testing.expectEqualStrings(expected_message, msg);
                vm.runtime.resetDiagArena();
            },
        },
    }
}

pub fn expectRuntimeError(source: []const u8, expected: revo.EvalErrorKind) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const program = try compileChecked(&vm, source);
    defer alloc.free(program);

    vm.mainFiber().program = program;
    const result = try revo.vm.exec.runReport(&vm);
    switch (result) {
        .ok => return error.ExpectedRuntimeFailure,
        .err => |failure| try std.testing.expectEqual(expected, failure.kind),
    }
}

pub fn expectRuntimeErrorInDir(module_dir: []const u8, source: []const u8, expected: revo.EvalErrorKind) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();
    vm.module_dir = module_dir;

    const source_name = try std.Io.Dir.path.join(alloc, &.{ module_dir, "<source>" });
    defer alloc.free(source_name);

    const result = try revo.module.runModule(&vm, source_name, source, false);
    switch (result) {
        .ok => return error.ExpectedRuntimeFailure,
        .err => |failure| try std.testing.expectEqual(expected, failure.kind),
    }
}

pub fn expectRuntimeFailure(
    source: []const u8,
    expected_kind: revo.EvalErrorKind,
    expected_line: u32,
    expected_column: u32,
    expected_message: []const u8,
) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const program = try compileChecked(&vm, source);
    defer alloc.free(program);

    vm.mainFiber().program = program;
    const result = try revo.vm.exec.runReport(&vm);
    switch (result) {
        .ok => return error.ExpectedRuntimeFailure,
        .err => |failure| {
            try std.testing.expectEqual(expected_kind, failure.kind);
            const span = diagnostic.primarySpan(failure.report).?;
            const msg = diagnostic.firstError(failure.report).?;
            try std.testing.expectEqual(expected_line, span.span.line);
            try std.testing.expectEqual(expected_column, span.span.column);
            try std.testing.expectEqualStrings(expected_message, msg);
        },
    }
}

pub fn expectRuntimeFailureWithMessage(
    source: []const u8,
    expected_kind: revo.EvalErrorKind,
    expected_message: []const u8,
) !void {
    var vm = try revo.VM.init(runtime());
    defer vm.deinit();

    const program = try compileChecked(&vm, source);
    defer alloc.free(program);

    vm.mainFiber().program = program;
    const result = try revo.vm.exec.runReport(&vm);
    switch (result) {
        .ok => return error.ExpectedRuntimeFailure,
        .err => |failure| {
            try std.testing.expectEqual(expected_kind, failure.kind);
            try std.testing.expectEqualStrings(
                expected_message,
                diagnostic.firstError(failure.report).?,
            );
        },
    }
}
