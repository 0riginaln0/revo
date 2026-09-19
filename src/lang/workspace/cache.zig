//! build + inspect caches and invalidation

const std = @import("std");

const common = @import("common.zig");
const diagnostic = @import("../diagnostic.zig");
const Parser = @import("../Parser.zig");
const pipeline = @import("../pipeline.zig");

const W = @import("../Workspace.zig");
const Workspace = W.Workspace;
const FileId = W.FileId;
const Snapshot = W.Snapshot;
const Analysis = W.Analysis;
const Symbol = W.Symbol;
const FnSig = W.FnSig;
const CacheEntry = W.CacheEntry;
const InspectCacheEntry = W.InspectCacheEntry;

/// check inspect cache and return cached Analysis if valid
pub fn inspectCached(
    self: *Workspace,
    alloc: std.mem.Allocator,
    snap: Snapshot,
    id: FileId,
    opts: pipeline.BuildOptions,
) !?Analysis {
    const cached = self.inspect_cache.get(id) orelse return null;
    if (cached.version != snap.version or !common.sameOpts(cached.opts, opts)) return null;
    const cached_diag = if (cached.diagnostics) |diag|
        try common.copyError(alloc, diag, snap.name, snap.text)
    else
        null;
    return Analysis{
        .snapshot = snap,
        .diagnostics = cached_diag,
        .cached = true,
        .symbols = try common.copySymbols(alloc, cached.symbols),
        .dependencies = try self.copyDeps(alloc, id),
    };
}

/// cache error state and return Analysis with diags
pub fn inspectParseError(
    self: *Workspace,
    alloc: std.mem.Allocator,
    snap: Snapshot,
    id: FileId,
    opts: pipeline.BuildOptions,
    err: Parser.ParseFailure,
) !Analysis {
    var report = try err.report.copy(alloc);
    report.source_name = try alloc.dupe(u8, snap.name);
    report.source = try alloc.dupe(u8, snap.text);

    const parse_error: pipeline.Error = .{ .parse = .{ .kind = err.kind, .report = report } };
    const cache_diag = try common.copyError(self.alloc, parse_error, snap.name, snap.text);
    errdefer pipeline.deinitError(self.alloc, cache_diag);

    const empty_syms = try self.alloc.alloc(Symbol, 0);
    errdefer self.alloc.free(empty_syms);

    const empty_deps = try self.alloc.alloc(FileId, 0);
    errdefer self.alloc.free(empty_deps);

    try putInspectCache(self, id, snap.version, opts, empty_syms, empty_deps, cache_diag, .empty, .init(self.alloc));
    return .{
        .snapshot = snap,
        .diagnostics = parse_error,
        .cached = false,
        .symbols = try alloc.alloc(Symbol, 0),
        .dependencies = try alloc.alloc(FileId, 0),
    };
}

// store build bytecode in cache
pub fn putCache(
    self: *Workspace,
    id: FileId,
    version: u32,
    opts: pipeline.BuildOptions,
    bytecode: pipeline.Bytecode,
    symbols: []Symbol,
    warnings: ?diagnostic.Report,
) !void {
    const entry = CacheEntry{
        .version = version,
        .opts = opts,
        .bytecode = bytecode,
        .warnings = warnings,
        .symbols = symbols,
    };
    if (self.cache.getPtr(id)) |slot| {
        common.deinitBytecode(self.alloc, slot.bytecode);
        common.freeSymbols(self.alloc, slot.symbols);
        if (slot.warnings) |*w| w.deinit(self.alloc);
        slot.* = entry;
    } else {
        try self.cache.put(id, entry);
    }
}

/// invalidate a file and all its transitive dependents
pub fn invalidateCache(self: *Workspace, id: FileId) void {
    var visited = std.AutoHashMap(FileId, void).init(self.alloc);
    defer visited.deinit();
    invalidateCacheImpl(self, id, &visited);
}

/// recursive invalidate; visited prevents cycle chokes
pub fn invalidateCacheImpl(
    self: *Workspace,
    id: FileId,
    visited: *std.AutoHashMap(FileId, void),
) void {
    if (visited.contains(id)) return;
    visited.put(id, {}) catch return;

    if (self.cache.fetchRemove(id)) |kv| {
        var val = kv.value;
        common.deinitBytecode(self.alloc, val.bytecode);
        common.freeSymbols(self.alloc, val.symbols);
        if (val.warnings) |*w| w.deinit(self.alloc);
    }
    if (self.inspect_cache.fetchRemove(id)) |kv| {
        common.freeSymbols(self.alloc, kv.value.symbols);
        self.alloc.free(kv.value.dependencies);
        if (kv.value.diagnostics) |diag| pipeline.deinitError(self.alloc, diag);
        var e = kv.value;
        e.deinit(self.alloc);
    }

    if (self.reverse_deps.get(id)) |dependents| {
        for (dependents) |dep| invalidateCacheImpl(self, dep, visited);
    }
}

/// free all build and inspect caches
pub fn clearCache(self: *Workspace) void {
    var it = self.cache.iterator();
    while (it.next()) |entry| {
        common.deinitBytecode(self.alloc, entry.value_ptr.bytecode);
        common.freeSymbols(self.alloc, entry.value_ptr.symbols);
        if (entry.value_ptr.warnings) |*w| w.deinit(self.alloc);
    }
    var inspect_it = self.inspect_cache.iterator();
    while (inspect_it.next()) |entry| {
        common.freeSymbols(self.alloc, entry.value_ptr.symbols);
        self.alloc.free(entry.value_ptr.dependencies);
        if (entry.value_ptr.diagnostics) |diag| {
            pipeline.deinitError(self.alloc, diag);
        }
        var e = entry.value_ptr.*;
        e.deinit(self.alloc);
    }
}

/// store results in the inspect cache (symbols + deps + diagnostics)
pub fn putInspectCache(
    self: *Workspace,
    id: FileId,
    version: u32,
    opts: pipeline.BuildOptions,
    symbols: []Symbol,
    dependencies: []FileId,
    diag: ?pipeline.Error,
    sig_map: std.StringHashMapUnmanaged(FnSig),
    docs: std.StringHashMap([]const u8),
) !void {
    const entry = InspectCacheEntry{
        .version = version,
        .opts = opts,
        .symbols = symbols,
        .dependencies = dependencies,
        .diagnostics = diag,
        .sig_map = sig_map,
        .docs = docs,
    };
    if (self.inspect_cache.getPtr(id)) |slot| {
        common.freeSymbols(self.alloc, slot.symbols);
        self.alloc.free(slot.dependencies);
        if (slot.diagnostics) |cached_d| pipeline.deinitError(self.alloc, cached_d);
        slot.deinit(self.alloc);
        slot.* = entry;
    } else {
        try self.inspect_cache.put(id, entry);
    }
}
