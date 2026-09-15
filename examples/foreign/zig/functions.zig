const revo = @import("revo");
const std = @import("std");

const ext = revo.ext;
const T = ext.T;
const VM = ext.VM;
const Data = ext.Data;
const HostResult = ext.HostResult;

const Impl = struct {
    pub fn zadd(vm: *VM, a: T.number, b: T.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(a + b));
    }

    pub fn zecho(vm: *VM, s: T.string) !HostResult {
        _ = vm;
        // ids pass through as-is, no re-intern needed
        return .data(Data.new.str(@intFromEnum(s)));
    }

    pub fn zsetglobal(vm: *VM, name: T.string, value: T.any) !HostResult {
        try vm.setGlobal(ext.str(vm, name), value);
        return .data(Data.new.num(1));
    }

    pub fn zconcat(vm: *VM, parts: T.table, sep: T.string) !HostResult {
        const separator = ext.str(vm, sep);
        const tab = try vm.tables.get(@intFromEnum(parts));

        var buf = try std.ArrayList(u8).initCapacity(vm.runtime.alloc, 32);
        defer buf.deinit(vm.runtime.alloc);
        for (tab.array.items, 0..) |item, i| {
            if (i > 0) try buf.appendSlice(vm.runtime.alloc, separator);
            const s_id = item.asString() orelse return .errType(0, "table of strings", "other");
            try buf.appendSlice(vm.runtime.alloc, vm.stringValue(s_id));
        }
        return .data(try vm.adoptDataStringNoDedup(try buf.toOwnedSlice(vm.runtime.alloc)));
    }
};

pub export const revo_native_bindings_ex = ext.bindingsFor(Impl);
