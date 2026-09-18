//! per-opcode histogram + vm-level event totals
//!
//! only collected when built with `-Dperf`; every bump compiles away
//! otherwise, so the dispatch loop pays nothing there
//! `enabled` is the one ctime gate

const std = @import("std");

const build_options = @import("build_options");
const opcode = @import("opcode.zig");
const Opcode = opcode.Opcode;

pub const enabled: bool = build_options.perf;

pub const OPCODE_COUNT: usize = @typeInfo(Opcode).@"enum".fields.len;

pub const PerfCounters = struct {
    opcode_counts: [OPCODE_COUNT]u64 = @splat(0),
    total: u64 = 0,
    gc_runs: u64 = 0,
    gc_bytes: u64 = 0,
    host_calls: u64 = 0,
    c_calls: u64 = 0,
    fibers_spawned: u64 = 0,
    closures_created: u64 = 0,

    pub fn reset(self: *PerfCounters) void {
        self.* = .{};
    }

    pub fn countOp(self: *PerfCounters, op: Opcode) void {
        self.opcode_counts[@intFromEnum(op)] += 1;
        self.total += 1;
    }

    pub fn countOpN(self: *PerfCounters, op: Opcode, n: usize) void {
        self.opcode_counts[@intFromEnum(op)] += n;
        self.total += n;
    }
};

pub fn printReport(counters: *const PerfCounters) void {
    std.debug.print("+-------- perf counters --------\n", .{});
    std.debug.print("| instrs  {d}\n", .{counters.total});
    std.debug.print("| gc      {d} runs / {d} bytes\n", .{ counters.gc_runs, counters.gc_bytes });
    std.debug.print("| calls   {d} host / {d} c\n", .{ counters.host_calls, counters.c_calls });
    std.debug.print("| spawned {d} fibers / {d} closures\n", .{ counters.fibers_spawned, counters.closures_created });

    var order: [OPCODE_COUNT]u8 = undefined;
    for (&order, 0..) |*slot, i| slot.* = @intCast(i);
    std.mem.sort(u8, &order, counters, struct {
        pub fn lessThan(c: *const PerfCounters, a: u8, b: u8) bool {
            return c.opcode_counts[a] > c.opcode_counts[b];
        }
    }.lessThan);

    for (order) |idx| {
        const n = counters.opcode_counts[idx];
        if (n == 0) break;
        const op: Opcode = @enumFromInt(idx);
        const pct = @as(f64, @floatFromInt(n)) * 100.0 / @as(f64, @floatFromInt(@max(counters.total, 1)));
        std.debug.print("|   {s: <18} {d: >10} ({d:.1}%)\n", .{ @tagName(op), n, pct });
    }
}

test "counters reset and count" {
    var c = PerfCounters{};
    c.countOp(.add);
    c.countOpN(.call, 3);
    c.gc_runs += 1;
    try std.testing.expectEqual(@as(u64, 4), c.total);
    try std.testing.expectEqual(@as(u64, 1), c.opcode_counts[@intFromEnum(Opcode.add)]);
    try std.testing.expectEqual(@as(u64, 3), c.opcode_counts[@intFromEnum(Opcode.call)]);
    try std.testing.expectEqual(@as(u64, 0), c.opcode_counts[@intFromEnum(Opcode.ret)]);
    c.reset();
    try std.testing.expectEqual(@as(u64, 0), c.total);
    try std.testing.expectEqual(@as(u64, 0), c.gc_runs);
}
