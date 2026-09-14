//! dependency graph: forward deps, reverse deps, closure

const std = @import("std");

const txt = @import("text.zig");

const W = @import("../Workspace.zig");
const Workspace = W.Workspace;
const FileId = W.FileId;

/// replace a file's dependency set; add/remove reverse deps as needed
pub fn updateDeps(self: *Workspace, id: FileId, new_deps: []FileId) !void {
    const old_deps = if (self.dependencies.fetchRemove(id)) |kv| kv.value else &.{};

    if (old_deps.len != 0) {
        for (old_deps) |dep| {
            if (!txt.containsId(new_deps, dep)) try removeReverseDep(self, dep, id);
        }
    }

    if (new_deps.len != 0) {
        for (new_deps) |dep| {
            if (!txt.containsId(old_deps, dep)) try addReverseDep(self, dep, id);
        }
        try self.dependencies.put(id, new_deps);
    } else {
        self.alloc.free(new_deps);
    }

    if (old_deps.len != 0) {
        self.alloc.free(old_deps);
    }
}

/// remove all deps for a file and clear reverse deps
pub fn removeDeps(self: *Workspace, id: FileId) void {
    if (self.dependencies.fetchRemove(id)) |kv| {
        for (kv.value) |dep| removeReverseDep(self, dep, id) catch {};
        self.alloc.free(kv.value);
    }
}

/// mark `id` as a dependent of `dep`
pub fn addReverseDep(self: *Workspace, dep: FileId, id: FileId) !void {
    const current = self.reverse_deps.get(dep);
    if (current) |items| {
        if (txt.containsId(items, id)) return;
        const next = try self.alloc.alloc(FileId, items.len + 1);
        @memcpy(next[0..items.len], items);
        next[items.len] = id;
        self.alloc.free(items);
        try self.reverse_deps.put(dep, next);
    } else {
        const next = try self.alloc.alloc(FileId, 1);
        next[0] = id;
        try self.reverse_deps.put(dep, next);
    }
}

/// remove `id` from `dep`'s reverse dependency list
pub fn removeReverseDep(self: *Workspace, dep: FileId, id: FileId) !void {
    const current = self.reverse_deps.get(dep) orelse return;
    var pos: ?usize = null;
    for (current, 0..) |item, idx| {
        if (item == id) {
            pos = idx;
            break;
        }
    }
    const idx = pos orelse return;
    if (current.len == 1) {
        self.alloc.free(current);
        _ = self.reverse_deps.remove(dep);
        return;
    }
    const next = try self.alloc.alloc(FileId, current.len - 1);
    @memcpy(next[0..idx], current[0..idx]);
    @memcpy(next[idx..], current[idx + 1 ..]);
    self.alloc.free(current);
    try self.reverse_deps.put(dep, next);
}

pub fn clearDeps(self: *Workspace) void {
    var it = self.dependencies.iterator();
    while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
    it = self.reverse_deps.iterator();
    while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
    self.dependencies.clearRetainingCapacity();
    self.reverse_deps.clearRetainingCapacity();
}

pub fn copyDeps(self: *Workspace, alloc: std.mem.Allocator, id: FileId) ![]FileId {
    const deps = self.dependencies.get(id) orelse return alloc.alloc(FileId, 0);
    return alloc.dupe(FileId, deps);
}

/// transitive closure of all dependencies
pub fn dependencyClosure(self: *Workspace, alloc: std.mem.Allocator, id: FileId) ![]FileId {
    var visited = std.AutoHashMap(FileId, void).init(alloc);
    defer visited.deinit();

    var out = try std.ArrayList(FileId).initCapacity(alloc, 4);
    errdefer out.deinit(alloc);

    try collectDependencyClosure(self, id, alloc, &visited, &out);
    return out.toOwnedSlice(alloc);
}

/// recursive deps walker; visited prevents cycles
pub fn collectDependencyClosure(
    self: *Workspace,
    id: FileId,
    alloc: std.mem.Allocator,
    visited: *std.AutoHashMap(FileId, void),
    out: *std.ArrayList(FileId),
) !void {
    const deps = self.dependencies.get(id) orelse return;
    for (deps) |dep| {
        if (visited.contains(dep)) continue;
        try visited.put(dep, {});
        try out.append(alloc, dep);
        try collectDependencyClosure(self, dep, alloc, visited, out);
    }
}
