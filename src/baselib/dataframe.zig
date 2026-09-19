const revo = @import("revo");
const root = @import("root.zig");
const specs = @import("specs.zig");
const std = @import("std");
const table_std = @import("table.zig");
// const alloc_pool = @import("alloc_pool.zig");
const Args = root.host.ArgTypes;

const math = std.math;
const typeof = root.typeof;
const memory = revo.memory;
const Value = memory.Value;
const VM = revo.VM;
const HostResult = root.host.HostResult;
const testing = revo.lang.test_helpers;
const table_methods = table_std.Impl;

// type Dataframe = table<string, table<any>>

pub const Impl = struct {

    // dataframe.select(Dataframe, table<string>) -> Dataframe
    pub fn select(vm: *VM, frame_table_id: Args.table, names_table_id: Args.table) !HostResult {
        const frame_table = try vm.tables.get(@intFromEnum(frame_table_id));
        const names_table = try vm.tables.get(@intFromEnum(names_table_id));
        const result_table_id = try vm.tables.create();
        const result_table = try vm.tables.get(result_table_id);

        // In order of strings given to the select() function
        for (names_table.array.items) |colname| {
            // if the array string is in the hashmap
            const maybe_coltable = frame_table.getRaw(colname, vm);
            if (maybe_coltable) |coltable| {
                // clone it, place it in the result table under the same string name
                const copied_table_id = switch (try table_methods.copy(vm, @enumFromInt(coltable.asTable().?))) {
                    .ok => |v| v.asTable().?,
                    .err => |e| return .{ .err = e },
                };
                try result_table.put(result_table_id, vm, colname, Value.new.table(copied_table_id));
            }
        }

        return .data(Value.new.table(result_table_id));
    }
};

pub const impls: []const specs.Impl = root.host.impls(Impl).val;

// frame.rename(Frame) -> Dataframe
// frame.arrange(Frame) -> Dataframe
// frame.unique(Frame) -> Dataframe
// frame.mutate(Frame) -> Dataframe
// frame.filter(Frame) -> Dataframe
// frame.summarize(Frame) -> Dataframe
// frame.group_by(Frame) -> Dataframe
// frame.gather(Frame) -> Dataframe
// frame.inner_join(Frame) -> Dataframe
// frame.stack(table<Dataframe>) -> Dataframe

test "frame functions and methods" {
    try testing.topTrue("{\"foos\" = {1, 2, 3}, \"bars\" = {4, 5, 6}, \"bazzes\" = {7, 8, 9}} |> dataframe.select({\"foos\", \"bazzes\"}) == {\"foos\" = {1, 2, 3}, \"bazzes\" = {7, 8, 9}}");
}
