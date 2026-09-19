const revo = @import("revo");
const std = @import("std");

const extension = revo.extension;
const Args = extension.ArgTypes;
const VM = extension.VM;
const Value = extension.Value;
const HostResult = extension.HostResult;

const Impl = struct {
    pub fn zadd(vm: *VM, a: Args.number, b: Args.number) !HostResult {
        _ = vm;
        return .data(Value.new.num(a + b));
    }

    pub fn zecho(vm: *VM, s: Args.string) !HostResult {
        _ = vm;
        // ids pass through as-is, no re-intern needed
        return .data(Value.new.str(@intFromEnum(s)));
    }

    pub fn zsetglobal(vm: *VM, name: Args.string, value: Args.any) !HostResult {
        try vm.setGlobal(extension.str(vm, name), value);
        return .data(Value.new.num(1));
    }

    pub fn zconcat(vm: *VM, parts: Args.table, sep: Args.string) !HostResult {
        const separator = extension.str(vm, sep);
        const tab = try vm.tables.get(@intFromEnum(parts));

        var buf = try std.ArrayList(u8).initCapacity(vm.runtime.alloc, 32);
        defer buf.deinit(vm.runtime.alloc);
        for (tab.array.items, 0..) |item, i| {
            if (i > 0) try buf.appendSlice(vm.runtime.alloc, separator);
            const s_id = item.asString() orelse return .errType(0, "table of strings", "other");
            try buf.appendSlice(vm.runtime.alloc, vm.stringValue(s_id));
        }
        return .data(try vm.adoptValueStringNoDedup(try buf.toOwnedSlice(vm.runtime.alloc)));
    }
};

pub export const revo_native_bindings_ex = extension.bindingsFor(Impl);
