//
// owned handles!
//
// while light `opaque` is a bare immediate; resource is what you want
// for handles with methods & cleanup
//
// a caller-owned ptr in a gc cell + a per-handle metatable:
// revo code can neither see nor overwrite the address.
// the cell frees at sweep, the pointee never
//

const std = @import("std");

const revo = @import("revo");
const mem = revo.memory;
const alloc_pool = @import("alloc_pool.zig");

/// hidden ptr + metatable; caller owns the pointee
pub const Resource = struct {
    ptr: ?*anyopaque,
    metatable: ?mem.TableID = null,
};

pub const ResourcePool = struct {
    alloc: std.mem.Allocator,
    // boxed like tables: get() stays valid across create()
    box_pool: std.heap.MemoryPool(Resource),
    resources: std.ArrayList(?*Resource),
    marks: std.DynamicBitSet,
    dead: std.ArrayList(mem.ResourceID),
    first: usize = alloc_pool.end,
    last: usize = alloc_pool.end,
    next: std.ArrayList(usize),

    pub fn init(alloc: std.mem.Allocator) !ResourcePool {
        return ResourcePool{
            .alloc = alloc,
            .box_pool = .empty,
            .resources = try .initCapacity(alloc, 4),
            .marks = try .initEmpty(alloc, 64),
            .dead = .empty,
            .next = try .initCapacity(alloc, 4),
        };
    }

    pub fn deinit(self: *ResourcePool) void {
        self.box_pool.deinit(self.alloc);
        self.resources.deinit(self.alloc);
        self.marks.deinit();
        self.dead.deinit(self.alloc);
        self.next.deinit(self.alloc);
    }

    pub fn create(self: *ResourcePool, ptr: ?*anyopaque) !mem.ResourceID {
        return alloc_pool.create(
            self.alloc,
            Resource,
            mem.ResourceID,
            &self.box_pool,
            &self.resources,
            &self.marks,
            &self.dead,
            &self.first,
            &self.last,
            &self.next,
            .{ .ptr = ptr },
        );
    }

    pub fn get(self: *ResourcePool, id: mem.ResourceID) !*Resource {
        if (id >= self.resources.items.len) return error.ResourceDNE;
        if (self.resources.items[id]) |r| return r;
        return error.ResourceDNE;
    }

    pub fn isValid(self: *const ResourcePool, id: mem.ResourceID) bool {
        return id < self.resources.items.len and self.resources.items[id] != null;
    }

    pub fn mark(self: *ResourcePool, id: mem.ResourceID, vm: *revo.VM) void {
        if (id >= self.resources.items.len) return;
        if (self.marks.isSet(id)) return;
        if (self.resources.items[id] == null) return;
        self.marks.set(id);
        vm.gc_mark_stack.append(vm.runtime.alloc, .{ .resource = id }) catch @panic("OOM in GC marking");
    }

    pub fn sweep(self: *ResourcePool) void {
        alloc_pool.sweep(
            self.alloc,
            Resource,
            mem.ResourceID,
            &self.box_pool,
            &self.resources,
            &self.marks,
            &self.dead,
            &self.first,
            &self.last,
            &self.next,
            freeResource,
        );
    }

    pub inline fn bytes(self: *const ResourcePool) usize {
        var total: usize = 0;
        var id = self.first;
        while (id != alloc_pool.end) {
            total += @sizeOf(Resource);
            id = self.next.items[id];
        }
        return total;
    }
};

fn freeResource(_: *Resource, _: std.mem.Allocator) void {}
