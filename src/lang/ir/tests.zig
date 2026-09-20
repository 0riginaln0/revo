//! optimizer tests, moved out of prod files so passes stay lean
//!   same coverage as before: end-to-end via pipeline.build plus hand-built ir

const std = @import("std");

const revo = @import("revo");
const VM = revo.VM;
const Opcode = revo.opcode.Opcode;
const Operand = revo.Operand;
const Register = revo.opcode.Register;

const Compiler = @import("../compiler/root.zig").Compiler;
const peepholeIr = @import("opt.zig").peepholeIr;
const pipeline = @import("../pipeline.zig");
const testing = @import("../test_helpers.zig");
const t = testing;

fn testRuntime() revo.Runtime {
    return .{
        .alloc = std.testing.allocator,
        .io = std.testing.io,
        .diag_alloc = std.testing.allocator,
        .diag_arena = null,
    };
}

/// hand-built ir has no spans; compact mirrors dce and expects one per
/// instruction, so fill in placeholders
fn appendSpans(compiler: *Compiler, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try compiler.spans.append(compiler.alloc, .{ .start = 0, .end = 0, .line = 1, .column = 1 });
    }
}

test "dce: arithmetic with unused result is eliminated" {
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    const built = try pipeline.build(&vm, .{ .text =
        \\let _ = 1 + 2
        \\42
    }, .{});
    try std.testing.expect(built == .ok);
    defer vm.runtime.alloc.free(built.ok.instructions);
    defer vm.runtime.alloc.free(built.ok.spans);

    for (built.ok.instructions) |inst| {
        if (inst.op == .add) return error.TestUnexpectedResult;
    }
}

test "dce regression tests" {
    try t.topNumber(
        \\let x = 1 + 2
        \\x
    , 3);

    try t.topNumber(
        \\if 1 == 1
        \\    42
        \\else
        \\    1 + 2
    , 42);

    try t.topNumber(
        \\fn f() do
        \\    let _ = 1 + 2
        \\    let _ = 3 * 4
        \\    42
        \\end
        \\f()
    , 42);

    try t.topNumber(
        \\do
        \\    1
        \\    2
        \\    3
        \\end
    , 3);

    try t.topNumber("1 + 2 * 3", 7);
    try t.topString(
        \\let s = "hello"
        \\s
    , "hello");
    try t.topNumber(
        \\let x = 10
        \\x + 5
    , 15);

    try t.topNumber(
        \\let x = 1 + 2
        \\let _ = x
        \\99
    , 99);

    // the then and else branches write the same shared branch register,
    // so a linear last-writer scan only keeps one of them. both must
    // survive or the if-expression returns a raw number instead of a bool
    try t.topNumber(
        \\let hold_count = 9297
        \\let queue_count = 23246
        \\fn f() do
        \\  if queue_count == 23246
        \\    hold_count == 9297
        \\  else
        \\    :false
        \\end
        \\if f() 1 else 0
    , 1);

    // a while loop's break value flows back through a register; dce must
    // not treat the loop result as dead just because it is written on both
    // the loop-back and fall-through paths
    try t.topNumber(
        \\fn f() do
        \\  let i = 0
        \\  while i < 3 do
        \\    i = i + 1
        \\  end
        \\  i
        \\end
        \\f()
    , 3);

    // the same loop but the break value is consumed, so its move must live
    try t.topNumber(
        \\let r = loop/l do
        \\  break/l 42
        \\end
        \\r
    , 42);
    try t.topAtom(
        \\let r = loop do
        \\  break 42
        \\end
        \\r
    , "loop");

    // a function whose dead leading arithmetic is eliminated, with a
    // conditional jump inside that must still reach the right branches
    try t.topNumber(
        \\fn f(x) do
        \\  7 * 8
        \\  9 + 10
        \\  if x == 1
        \\    10
        \\  else
        \\    20
        \\  end
        \\if f(1) 100 else 200
    , 100);

    // the function's first statement is a discarded expression, so the
    // template addr points at a now-dead instruction, it has2 be remapped
    // or the call lands on the wrong bytecode
    try t.topNumber(
        \\fn f() do
        \\  1 + 2
        \\  42
        \\end
        \\f()
    , 42);
}

test "dce: side-effecting calls are never eliminated" {
    // yeah i know. too hard to figure out whether it really side-effects or not
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    const built = try pipeline.build(&vm, .{ .text =
        \\fn f() 42
        \\let _ = f()
        \\1
    }, .{});
    try std.testing.expect(built == .ok);
    defer vm.runtime.alloc.free(built.ok.instructions);
    defer vm.runtime.alloc.free(built.ok.spans);

    var has_call = false;
    for (built.ok.instructions) |inst| {
        if (inst.op == .call) has_call = true;
    }
    try std.testing.expect(has_call);
}

test "dce: dead move after break is eliminated" {
    // the break's move is a pure register copy into a loop-result register
    // that nothing reads; register liveness must drop it (it used to be
    // treated as unconditionally side-effecting)
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    const built = try pipeline.build(&vm, .{ .text =
        \\loop do
        \\  break
        \\  99
        \\end
        \\42
    }, .{});
    try std.testing.expect(built == .ok);
    defer vm.runtime.alloc.free(built.ok.instructions);
    defer vm.runtime.alloc.free(built.ok.spans);

    for (built.ok.instructions) |inst| {
        if (inst.op == .move) return error.TestUnexpectedResult;
    }
}

test "dce: dead statements after a break are eliminated" {
    // `1 + 2` is pure arithmetic whose result nothing reads
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    const built = try pipeline.build(&vm, .{ .text =
        \\do
        \\  1 + 2
        \\  42
        \\end
    }, .{});
    try std.testing.expect(built == .ok);
    defer vm.runtime.alloc.free(built.ok.instructions);
    defer vm.runtime.alloc.free(built.ok.spans);

    for (built.ok.instructions) |inst| {
        if (inst.op == .add) return error.TestUnexpectedResult;
    }
}

test "dce: folded constants and dead operands are both removed" {
    // `(1 + 2) * 3` folds to a single constant, and the load_small_int
    // operands of the folded instructions are reclaimed by dce
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    const built = try pipeline.build(&vm, .{ .text =
        \\let _ = (1 + 2) * 3
        \\42
    }, .{});
    try std.testing.expect(built == .ok);
    defer vm.runtime.alloc.free(built.ok.instructions);
    defer vm.runtime.alloc.free(built.ok.spans);

    for (built.ok.instructions) |inst| {
        switch (inst.op) {
            .add, .mul, .pow => return error.TestUnexpectedResult,
            else => {},
        }
    }
}

test "peephole: add zero folds away" {
    // `x + 0` is a register no-op and must disappear entirely
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    const built = try pipeline.build(&vm, .{ .text =
        \\fn f(x) do
        \\  x + 0
        \\end
        \\f(3)
    }, .{});
    try std.testing.expect(built == .ok);
    defer vm.runtime.alloc.free(built.ok.instructions);
    defer vm.runtime.alloc.free(built.ok.spans);

    for (built.ok.instructions) |inst| {
        if (inst.op == .add or inst.op == .move) return error.TestUnexpectedResult;
    }
}

test "peephole regressions" {
    try t.topNumber("fn f(x) do x + 0 end\nf(3)", 3);
    try t.topNumber("fn f(x) do 0 + x end\nf(3)", 3);
    try t.topNumber("fn f(x) do x + 1 end\nf(3)", 4);
    try t.topNumber("fn f(x) do 1 + x end\nf(3)", 4);
    try t.topNumber("fn f(x) do x * 1 end\nf(3)", 3);
    try t.topNumber("fn f(x) do 1 * x end\nf(3)", 3);
    try t.topNumber("fn f(x) do x * 2 end\nf(3)", 6);
    try t.topNumber("fn f(x) do x - 0 end\nf(3)", 3);
    try t.topNumber("fn f(x) do x / 1 end\nf(3)", 3);
    try t.topNumber("fn f(x) do x // 1 end\nf(3)", 3);
    try t.topNumber("fn f(x) do x - 1 end\nf(3)", 2);
    try t.topNumber("fn f(x) do 0 - x end\nf(3)", -3);
    try t.topNumber("fn f(x) do x * 0 end\nf(3)", 0);
    try t.topNumber("fn f(x) do 0 * x end\nf(3)", 0);
    try t.topString("fn f(x) do x * 1 end\nf(\"ab\")", "ab");

    // the folded result is consumed by a later expression, so the peephole
    // must keep the dataflow (via the register) intact
    try t.topNumber(
        \\fn f(x) do
        \\  let y = x + 0
        \\  y * 2
        \\end
        \\f(5)
    , 10);
}

test "peephole: store then self-load is a no-op" {
    // `x = expr; x` reloads a slot into the same register that just stored
    // it: the load is a no-op and must be dropped, the store stays
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.store_local, &.{}, false, 1, 1);
    _ = try compiler.record(.load_local, &.{}, false, 1, 1);
    _ = try compiler.record(.ret, &.{}, false, 1, 0);
    try appendSpans(&compiler, 4);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 3), insts.len);
    for (insts) |inst| {
        if (inst.opcode == .load_local and inst.op_arg == 1) return error.TestUnexpectedResult;
    }
}

test "peephole: store then self-load with a dead register write survives" {
    // if the stored register is overwritten before the reload, the load is a
    // genuine restore and must stay
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.store_local, &.{}, false, 1, 1);
    _ = try compiler.record(.load_small_int, &.{}, false, 1, 9);
    _ = try compiler.record(.load_local, &.{}, false, 1, 1);
    _ = try compiler.record(.ret, &.{}, false, 1, 0);
    try appendSpans(&compiler, 5);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 5), insts.len);
    var loads: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .load_local and inst.op_arg == 1) loads += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), loads);
}

test "peephole: store then self-load survives a slot rewrite" {
    // rewriting the slot between store and load makes the reload load the new
    // value, so it is not a no-op
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.store_local, &.{}, false, 1, 1);
    _ = try compiler.record(.load_local, &.{}, false, 2, 0);
    _ = try compiler.record(.store_local, &.{}, false, 2, 1);
    _ = try compiler.record(.load_local, &.{}, false, 1, 1);
    _ = try compiler.record(.ret, &.{}, false, 1, 0);
    try appendSpans(&compiler, 6);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 6), insts.len);
    var loads: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .load_local) loads += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), loads);
}

test "peephole: self move is eliminated" {
    // `move r1 <- A` where A already writes r1 is a register no-op; dce
    // keeps it because the register is live, but it must be dropped here
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    const a = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.move, &.{.{ .inst = a }}, false, 1, 0);
    _ = try compiler.record(.ret, &.{}, false, 1, 0);
    try appendSpans(&compiler, 3);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 2), insts.len);
    for (insts) |inst| {
        if (inst.opcode == .move) return error.TestUnexpectedResult;
    }
}

test "peephole: move into a table_set_atom register survives" {
    // `table_set_atom` reads `result_reg` (the table) and writes it back, so
    // a move feeding it is not dead even though the register is "overwritten"
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.table_new, &.{}, false, 1, 0);
    _ = try compiler.record(.move, &.{.{ .reg = 1 }}, false, 2, 0);
    _ = try compiler.record(.load_small_int, &.{}, false, 3, 41);
    _ = try compiler.record(.table_set_atom, &.{}, false, 2, 212);
    _ = try compiler.record(.ret, &.{}, false, 2, 0);
    try appendSpans(&compiler, 5);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 5), insts.len);
    var moves: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .move) moves += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), moves);
}

test "peephole: field-assign copy folds into the setter" {
    // `t.field = value` compiles to a dup of the object so `table_set_atom`
    // can read object and value back-to-back; the dup must fold away and the
    // setter must read the value from the shifted-down register
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    const obj = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.move, &.{.{ .inst = obj }}, false, 2, 0);
    const vo = try compiler.record(.load_local, &.{}, false, 3, 0);
    const vg = try compiler.record(.table_get_atom, &.{.{ .inst = vo }}, false, 3, 0);
    const one = try compiler.record(.load_small_int, &.{}, false, 4, 1);
    _ = try compiler.record(.add, &.{ .{ .inst = vg }, .{ .inst = one } }, false, 3, 0);
    _ = try compiler.record(.table_set_atom, &.{.{ .inst = vg }}, false, 2, 0);
    _ = try compiler.record(.load_local, &.{}, false, 2, 1);
    _ = try compiler.record(.ret, &.{}, false, 2, 0);
    try appendSpans(&compiler, 9);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 7), insts.len);
    for (insts) |inst| {
        if (inst.opcode == .move) return error.TestUnexpectedResult;
    }
    for (insts) |inst| {
        if (inst.opcode == .table_set_atom) {
            try std.testing.expectEqual(@as(Register, 1), inst.result_reg);
        }
    }
}

test "peephole: field-assign result read back collapses into the shift" {
    // an assignment whose value is used compiles to `table_set_atom` followed
    // by a `table_get_atom` that reads the dup register back; that readback
    // returns exactly the stored value, so the shift folds it away: the value
    // lands in the result register and the copy and readback both drop. the
    // value expression's own `t.field` reload also folds onto the object load
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    const obj = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.move, &.{.{ .inst = obj }}, false, 2, 0);
    const vo = try compiler.record(.load_local, &.{}, false, 3, 0);
    const vg = try compiler.record(.table_get_atom, &.{.{ .inst = vo }}, false, 3, 0);
    const one = try compiler.record(.load_small_int, &.{}, false, 4, 1);
    _ = try compiler.record(.add, &.{ .{ .inst = vg }, .{ .inst = one } }, false, 3, 0);
    _ = try compiler.record(.table_set_atom, &.{.{ .inst = vg }}, false, 2, 0);
    _ = try compiler.record(.table_get_atom, &.{.{ .inst = obj }}, false, 2, 0);
    _ = try compiler.record(.ret, &.{}, false, 2, 0);
    try appendSpans(&compiler, 9);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 6), insts.len);
    for (insts) |inst| {
        if (inst.opcode == .move) return error.TestUnexpectedResult;
    }
    var gets: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .table_get_atom) gets += 1;
        if (inst.opcode == .table_set_atom) {
            try std.testing.expectEqual(@as(Register, 1), inst.result_reg);
        }
        if (inst.opcode == .ret) {
            try std.testing.expectEqual(@as(Register, 2), inst.result_reg);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), gets);
}

test "peephole: field-assign readback of a different field survives" {
    // the readback reads a different field than the setter wrote, so the
    // shifted value is not what the result wants and the readback must stay.
    // the object load is reused instead of a dup: the readback reads the
    // object directly, so the copy and the value reload both fold away
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    const obj = try compiler.record(.load_local, &.{}, false, 1, 0);
    _ = try compiler.record(.move, &.{.{ .inst = obj }}, false, 2, 0);
    const vo = try compiler.record(.load_local, &.{}, false, 3, 0);
    const vg = try compiler.record(.table_get_atom, &.{.{ .inst = vo }}, false, 3, 0);
    _ = try compiler.record(.table_set_atom, &.{.{ .inst = vg }}, false, 2, 0);
    _ = try compiler.record(.table_get_atom, &.{.{ .inst = obj }}, false, 2, 1);
    _ = try compiler.record(.ret, &.{}, false, 2, 0);
    try appendSpans(&compiler, 7);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 5), insts.len);
    var moves: usize = 0;
    var readback_field: ?Operand = null;
    for (insts) |inst| {
        if (inst.opcode == .move) moves += 1;
        if (inst.opcode == .table_get_atom and inst.op_arg == 1) readback_field = inst.op_arg;
    }
    try std.testing.expectEqual(@as(usize, 0), moves);
    // the readback of the other field must still read that field
    try std.testing.expectEqual(@as(?Operand, 1), readback_field);
}

test "peephole: field refetch after setter folds away" {
    // `word.count = word.count + 1; word.count` reloads the object to read the
    // field the setter just wrote; the value register still holds the stored
    // value, so the reload and refetch both drop
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_local, &.{}, false, 6, 1);
    _ = try compiler.record(.load_local, &.{}, false, 7, 1);
    const vg = try compiler.record(.table_get_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[1] }}, false, 7, 0);
    _ = try compiler.record(.load_small_int, &.{}, false, 8, 1);
    const add = try compiler.record(.add, &.{ .{ .inst = vg }, .{ .inst = compiler.ir_builder.instructions.items[3] } }, false, 7, 0);
    _ = try compiler.record(.table_set_atom, &.{.{ .inst = add }}, false, 6, 0);
    _ = try compiler.record(.load_local, &.{}, false, 7, 1);
    _ = try compiler.record(.table_get_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[6] }}, false, 7, 0);
    _ = try compiler.record(.ret, &.{}, false, 7, 0);
    try appendSpans(&compiler, 9);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 6), insts.len);
    // only the value expression's `word.count` read remains; the reload and
    // the refetch after the setter are gone, so the setter feeds ret directly
    var gets: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .table_get_atom) gets += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), gets);
    try std.testing.expectEqual(Opcode.table_set_atom, insts[4].opcode);
    try std.testing.expectEqual(Opcode.ret, insts[5].opcode);
}

test "peephole: field refetch of a rewritten slot survives" {
    // rewriting the slot between the setter and the refetch makes the reload
    // read a different object, so the refetch is a genuine read and must stay
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_local, &.{}, false, 6, 1);
    _ = try compiler.record(.load_local, &.{}, false, 7, 1);
    _ = try compiler.record(.table_get_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[1] }}, false, 7, 0);
    _ = try compiler.record(.load_small_int, &.{}, false, 8, 1);
    _ = try compiler.record(.add, &.{ .{ .inst = compiler.ir_builder.instructions.items[2] }, .{ .inst = compiler.ir_builder.instructions.items[3] } }, false, 7, 0);
    _ = try compiler.record(.table_set_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[4] }}, false, 6, 0);
    _ = try compiler.record(.load_local, &.{}, false, 7, 1);
    _ = try compiler.record(.store_local, &.{}, false, 7, 1);
    _ = try compiler.record(.table_get_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[7] }}, false, 7, 0);
    _ = try compiler.record(.ret, &.{}, false, 7, 0);
    try appendSpans(&compiler, 10);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 9), insts.len);
    var gets: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .table_get_atom) gets += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), gets);
}

test "peephole: field refetch of a different slot survives" {
    // the reload reads a different slot than the setter's object, so the
    // refetch reads a different object and must stay
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_local, &.{}, false, 6, 1);
    _ = try compiler.record(.load_local, &.{}, false, 7, 2);
    _ = try compiler.record(.table_set_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[1] }}, false, 6, 0);
    _ = try compiler.record(.load_local, &.{}, false, 7, 3);
    _ = try compiler.record(.table_get_atom, &.{.{ .inst = compiler.ir_builder.instructions.items[3] }}, false, 7, 0);
    _ = try compiler.record(.ret, &.{}, false, 7, 0);
    try appendSpans(&compiler, 6);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 6), insts.len);
    var gets: usize = 0;
    for (insts) |inst| {
        if (inst.opcode == .table_get_atom) gets += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), gets);
}

test "peephole: jump to next instruction is eliminated" {
    // a jump whose target is the very next instruction is a no-op
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_small_int, &.{}, false, 0, 1);
    _ = try compiler.record(.jump, &.{}, false, 0, 2);
    _ = try compiler.record(.ret, &.{}, false, 0, 0);
    try appendSpans(&compiler, 3);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 2), insts.len);
    for (insts) |inst| {
        if (inst.opcode == .jump) return error.TestUnexpectedResult;
    }
}

test "peephole: branch inversion removes a jump" {
    // `jump_if_false rA, L1; jump L2; L1:` inverts to
    // `jump_if_true rA, L2; L1:` when L1 is the very next slot, dropping
    // the unconditional jump
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.load_small_int, &.{}, false, 0, 1);
    _ = try compiler.record(.jump_if_false, &.{}, false, 0, 3);
    _ = try compiler.record(.jump, &.{}, false, 0, 4);
    _ = try compiler.record(.ret, &.{}, false, 0, 0);
    _ = try compiler.record(.ret, &.{}, false, 0, 0);
    try appendSpans(&compiler, 5);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 4), insts.len);
    for (insts) |inst| {
        if (inst.opcode == .jump) return error.TestUnexpectedResult;
    }
    try std.testing.expectEqual(Opcode.jump_if_true, insts[1].opcode);
    try std.testing.expectEqual(@as(usize, 3), insts[1].op_arg);
}

test "peephole: jump chains are threaded" {
    // `jump 1; 1: jump 2; 2: ret` folds the chain so both jumps target the
    // final destination
    var vm = try VM.init(testRuntime());
    defer vm.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var compiler = try Compiler.init(&vm, false, arena.allocator(), std.testing.allocator);
    defer compiler.deinit();

    _ = try compiler.record(.jump, &.{}, false, 0, 1);
    _ = try compiler.record(.jump, &.{}, false, 0, 3);
    _ = try compiler.record(.load_small_int, &.{}, false, 0, 9);
    _ = try compiler.record(.ret, &.{}, false, 0, 0);
    try appendSpans(&compiler, 4);

    try peepholeIr(&compiler);

    const insts = compiler.ir_builder.instructions.items;
    try std.testing.expectEqual(@as(usize, 4), insts.len);
    try std.testing.expectEqual(@as(usize, 3), insts[0].op_arg);
    try std.testing.expectEqual(@as(usize, 3), insts[1].op_arg);
}
