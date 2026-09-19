//! markdown hover + definition-line rendering

const std = @import("std");

const revo = @import("revo");

const common = @import("common.zig");
const pipeline = @import("../pipeline.zig");
const txt = @import("text.zig");
const type_syntax = @import("../type_syntax.zig");

const W = @import("../Workspace.zig");
const Workspace = W.Workspace;
const FileId = W.FileId;
const Position = W.Position;
const Range = W.Range;
const Hover = W.Hover;
const Symbol = W.Symbol;

/// markdown hover: kind, type, definition source, location
pub fn hover(
    self: *Workspace,
    alloc: std.mem.Allocator,
    id: FileId,
    pos: Position,
    opts: pipeline.BuildOptions,
) !?Hover {
    var analysis = try self.inspectDetailed(alloc, id, opts);
    defer analysis.deinit(alloc);
    const snap = analysis.snapshot;
    const name = txt.wordAtPosition(snap.text, pos) orelse return null;

    // baselib fallback; when name not bound in the ast
    if (try self.definition(alloc, id, pos, opts) == null) {
        if (revo.baselib.specs.find(name)) |spec| {
            var buf = std.Io.Writer.Allocating.init(alloc);
            defer buf.deinit();
            try buf.writer.writeAll("```revo\n");
            try revo.baselib.specs.renderSignature(&buf.writer, spec.*);
            try buf.writer.writeAll("\n```");
            if (spec.doc.len > 0) {
                try buf.writer.print("\n\n{s}", .{spec.doc});
            }
            const text = try buf.toOwnedSlice();
            return .{
                .text = text,
                .range = txt.wordRangeAt(snap.text, pos) orelse .{
                    .start = pos,
                    .end = .{
                        .line = pos.line,
                        .character = pos.character + @as(u32, @intCast(name.len)),
                    },
                },
            };
        }
        //
        // member of an imported module: `mod.member` - show its definition
        if (txt.moduleMemberAt(snap.text, pos)) |mod_name| {
            const fid = self.resolveDepId(alloc, id, mod_name) orelse id;
            const mod_syms = self.symbolsFromDep(alloc, fid) catch null;
            if (mod_syms) |ms| {
                defer common.freeSymbols(alloc, @constCast(ms));
                for (ms) |s| {
                    if (!std.mem.eql(u8, s.name, name)) continue;
                    const sym_tn = if (s.type_name) |ti| try type_syntax.formatTypeOpts(alloc, ti, .{}) else "";
                    defer if (sym_tn.len > 0) alloc.free(sym_tn);

                    const display = try renderDefinition(alloc, name, sym_tn, self, fid);
                    defer alloc.free(display);
                    var buf = std.Io.Writer.Allocating.init(alloc);
                    defer buf.deinit();

                    try buf.writer.print("```revo\n{s}\n```", .{display});
                    return .{
                        .text = try buf.toOwnedSlice(),
                        .range = txt.wordRangeAt(snap.text, pos) orelse .{
                            .start = pos,
                            .end = .{
                                .line = pos.line,
                                .character = pos.character + @as(u32, @intCast(name.len)),
                            },
                        },
                    };
                }
            }
        }
        return null;
    }
    const def = try self.definition(alloc, id, pos, opts) orelse return null;

    // look up type in the definition file (may differ from current file)
    var type_name: []const u8 = "";
    var record_display: []const u8 = "";
    if (def.file_id == id) {
        for (analysis.symbols) |sym| {
            if (std.mem.eql(u8, sym.name, name) and
                sym.range.start.line == def.range.start.line)
            {
                type_name = if (sym.type_name) |ti| try type_syntax.formatTypeOpts(alloc, ti, .{}) else "";
                record_display = try renderRecordDisplay(alloc, sym);
                break;
            }
        }
    } else {
        var def_analysis = try self.inspectDetailed(alloc, def.file_id, opts);
        defer def_analysis.deinit(alloc);
        for (def_analysis.symbols) |sym| {
            if (std.mem.eql(u8, sym.name, name)) {
                type_name = if (sym.type_name) |ti| try type_syntax.formatTypeOpts(alloc, ti, .{}) else "";
                record_display = try renderRecordDisplay(alloc, sym);
                break;
            }
        }
    }
    defer if (type_name.len > 0) alloc.free(type_name);
    defer if (record_display.len > 0) alloc.free(record_display);

    // for import modules, show exported symbols with full signatures
    if (self.resolveDepId(alloc, id, name)) |dep_id| {
        const mod_syms = self.symbolsFromDep(alloc, dep_id) catch null;
        if (mod_syms) |ms| {
            defer common.freeSymbols(alloc, @constCast(ms));

            if (ms.len > 0) {
                var buf = std.Io.Writer.Allocating.init(alloc);
                defer buf.deinit();
                try buf.writer.print("module `{s}`\n\n```revo\n", .{name});

                for (ms) |s| {
                    if (try self.fnSig(alloc, dep_id, s.name) != null) {
                        const sym_tn = if (s.type_name) |ti| try type_syntax.formatTypeOpts(alloc, ti, .{}) else "";
                        defer if (sym_tn.len > 0) alloc.free(sym_tn);

                        const display = try renderDefinition(alloc, s.name, sym_tn, self, dep_id);
                        defer alloc.free(display);

                        try buf.writer.writeAll(display);
                    } else {
                        if (self.snapshot(dep_id)) |ss| {
                            var line = txt.sourceLine(ss.text, s.range.start.line);
                            line = std.mem.trim(u8, line, " \t\r");
                            line = txt.stripPub(line);
                            try buf.writer.writeAll(line);
                        } else try buf.writer.writeAll(s.name);
                    }
                    try buf.writer.writeByte('\n');
                }
                try buf.writer.writeAll("```");

                return .{
                    .text = try buf.toOwnedSlice(),
                    .range = def.range,
                };
            }
        }
    }

    var doc_text: []const u8 = "";
    if (self.inspect_cache.getPtr(def.file_id)) |cache| {
        if (cache.docs.get(name)) |d| doc_text = d;
    }
    const display = blk: {
        if (try self.fnSig(alloc, def.file_id, name) != null)
            break :blk try renderDefinition(alloc, name, type_name, self, def.file_id);
        if (record_display.len > 0) break :blk try alloc.dupe(u8, record_display);
        if (self.snapshot(def.file_id)) |ss|
            break :blk try renderBindingLine(alloc, ss.text, def.range, type_name);
        break :blk try renderDefinition(alloc, name, type_name, self, def.file_id);
    };
    defer alloc.free(display);
    var buf = std.Io.Writer.Allocating.init(alloc);
    defer buf.deinit();
    try buf.writer.writeAll("```revo\n");
    try buf.writer.writeAll(display);
    try buf.writer.writeAll("\n```");
    if (doc_text.len > 0) {
        try buf.writer.print("\n\n{s}", .{doc_text});
    }
    // cross-file defs: their range is meaningless in this file
    const range: Range = if (def.file_id == id)
        def.range
    else
        (txt.wordRangeAt(snap.text, pos) orelse def.range);
    return .{
        .text = try buf.toOwnedSlice(),
        .range = range,
    };
}

/// hover rendering for a name declared in file `id`, null if not declared there
pub fn hoverByName(
    self: *Workspace,
    alloc: std.mem.Allocator,
    id: FileId,
    name: []const u8,
) !?[]const u8 {
    _ = try self.inspectDetailed(alloc, id, .{});
    const cache = self.inspect_cache.getPtr(id) orelse return null;

    const doc = cache.docs.get(name);
    const sig = cache.sig_map.get(name);

    var sym_range: ?Range = null;
    var type_name: []const u8 = "";
    defer if (type_name.len > 0) alloc.free(type_name);
    for (cache.symbols) |sym| {
        if (!std.mem.eql(u8, sym.name, name)) continue;
        sym_range = sym.range; // last binding wins
        if (sym.type_name) |ti| {
            if (type_name.len > 0) alloc.free(type_name);
            type_name = try type_syntax.formatTypeOpts(alloc, ti, .{});
        }
    }
    if (doc == null and sig == null and sym_range == null) return null;

    var buf = std.Io.Writer.Allocating.init(alloc);
    defer buf.deinit();
    if (sig != null) {
        const display = try renderDefinition(alloc, name, type_name, self, id);
        defer alloc.free(display);
        try buf.writer.writeAll(display);
    } else if (sym_range) |def_range| {
        if (self.snapshot(id)) |ss| {
            const line = try renderBindingLine(alloc, ss.text, def_range, type_name);
            defer alloc.free(line);
            try buf.writer.writeAll(line);
        } else {
            try buf.writer.writeAll(name);
        }
    } else {
        try buf.writer.writeAll(name);
    }
    if (doc) |d| try buf.writer.print("\n\n{s}", .{d});
    return try buf.toOwnedSlice();
}

/// `t: {name: string = "me"}`
///
/// for record-typed bindings with known literal values
/// "" when inapplicable (caller falls back)
fn renderRecordDisplay(alloc: std.mem.Allocator, sym: Symbol) ![]const u8 {
    const ti = sym.type_name orelse return "";
    if (ti.tag != .table) return "";
    if (ti.tag.table.fields == null) return "";
    const previews = sym.field_values orelse return "";
    if (previews.len == 0) return "";

    var buf = std.Io.Writer.Allocating.init(alloc);
    errdefer buf.deinit();
    try type_syntax.printType(ti, &buf.writer, .{ .values = previews });
    const record = try buf.toOwnedSlice();
    defer alloc.free(record);

    return try std.fmt.allocPrint(alloc, "{s}: {s}", .{ sym.name, record });
}

/// a value binding's source line, pub-stripped, `(type = t)` appended if
/// the inferred type isn't visible in it
fn renderBindingLine(
    alloc: std.mem.Allocator,
    text: []const u8,
    def_range: Range,
    type_name: []const u8,
) ![]const u8 {
    var line = txt.sourceLine(text, def_range.start.line);
    line = std.mem.trim(u8, line, " \t\r");
    line = txt.stripPub(line);
    if (type_name.len > 0 and std.mem.find(u8, line, type_name) == null)
        return std.fmt.allocPrint(alloc, "{s}\n(type = {s})", .{ line, type_name });
    return alloc.dupe(u8, line);
}

/// format a definition line: fn name(p1: t1, ...) -> ret when fnSig
/// is available, otherwise just name or type_name
pub fn renderDefinition(
    alloc: std.mem.Allocator,
    name: []const u8,
    type_name: []const u8,
    ws: *Workspace,
    file_id: FileId,
) ![]const u8 {
    if (try ws.fnSig(alloc, file_id, name)) |sig| {
        var buf = std.Io.Writer.Allocating.init(alloc);
        defer buf.deinit();

        try buf.writer.print("fn {s}", .{name});
        if (sig.type_params_text) |tps| try buf.writer.writeAll(tps);
        try buf.writer.writeByte('(');

        for (sig.params, 0..) |p, i| {
            if (i > 0) try buf.writer.print(", ", .{});
            try buf.writer.writeAll(p.name);
            if (p.optional) try buf.writer.writeByte('?');
            if (p.type_name) |ti| {
                const pt = try type_syntax.formatTypeOpts(alloc, ti, .{});
                defer alloc.free(pt);
                try buf.writer.print(": {s}", .{pt});
            }
        }

        try buf.writer.writeByte(')');
        if (sig.return_type) |rt| {
            const rt_str = try type_syntax.formatTypeOpts(alloc, rt, .{});
            try buf.writer.print(" -> {s}", .{rt_str});
        }

        return buf.toOwnedSlice();
    }
    if (type_name.len > 0 and std.mem.startsWith(u8, type_name, "fn(")) {
        return std.fmt.allocPrint(alloc, "fn {s}{s}", .{ name, type_name[2..] });
    }
    if (type_name.len > 0)
        return alloc.dupe(u8, type_name);
    return alloc.dupe(u8, name);
}

test "workspace hover shows record field values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ws = try Workspace.init(alloc);
    defer ws.deinit();

    const source =
        \\let t = {
        \\  name = "me",
        \\}
        \\t
    ;
    const id = try ws.open("<test>", source, .{});
    const query_opts: pipeline.BuildOptions = .{
        .include_baselib_macros = false,
        .install_debug_info = false,
        .test_mode = false,
    };

    var hov = try ws.hover(alloc, id, .{ .line = 4, .character = 1 }, query_opts);
    try std.testing.expect(hov != null);
    defer if (hov) |*h| h.deinit(alloc);
    try std.testing.expect(std.mem.find(u8, hov.?.text, "{name: string = \"me\"}") != null);
}

test "workspace hover over lib import manifest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const query_opts: pipeline.BuildOptions = .{
        .include_baselib_macros = false,
        .install_debug_info = false,
        .test_mode = true,
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extension.so", .data = "" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "extension.d.rv", .data =
        \\pub declare add = fn(a: number, b: number) -> number
        \\pub declare concat = fn(parts: table, sep: string) -> string
    });
    var dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const dir_n = try tmp.dir.realPath(std.testing.io, &dir_buf);
    const dir_path = dir_buf[0..dir_n];

    var vm = try revo.VM.init(.{ .alloc = alloc, .io = std.testing.io, .diag_alloc = alloc });
    defer vm.deinit();
    var ws = try Workspace.initWithVm(&vm, alloc);
    defer ws.deinit();

    const script = try std.fmt.allocPrint(alloc, "{s}/app.rv", .{dir_path});
    defer alloc.free(script);
    const id = try ws.open(script,
        \\import "extension.so"
        \\print(extension.concat({"a", "b"}, "-"))
    , .{});

    var hov = try ws.hover(alloc, id, .{ .line = 1, .character = 11 }, query_opts);
    defer if (hov) |*h| h.deinit(alloc);
    try std.testing.expect(hov != null);
    try std.testing.expect(std.mem.find(u8, hov.?.text, "module `extension`") != null);
    try std.testing.expect(std.mem.find(u8, hov.?.text, "concat") != null);
    // range covers just the module name inside the import statement
    try std.testing.expectEqual(@as(u32, 1), hov.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 9), hov.?.range.start.character);
    try std.testing.expectEqual(@as(u32, 18), hov.?.range.end.character);

    var hov2 = try ws.hover(alloc, id, .{ .line = 2, .character = 22 }, query_opts);
    defer if (hov2) |*h| h.deinit(alloc);
    try std.testing.expect(hov2 != null);
    try std.testing.expect(std.mem.find(u8, hov2.?.text, "fn concat(parts: table, sep: string) -> string") != null);
    // member def lives in the manifest; the range must be the call-site word
    try std.testing.expectEqual(@as(u32, 2), hov2.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 17), hov2.?.range.start.character);
    try std.testing.expectEqual(@as(u32, 23), hov2.?.range.end.character);
}

test "workspace hover over bare fn definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const query_opts: pipeline.BuildOptions = .{
        .include_baselib_macros = false,
        .install_debug_info = false,
        .test_mode = true,
    };

    var ws = try Workspace.init(alloc);
    defer ws.deinit();

    const id = try ws.open("<test>", "let x = 42\n\nfn say_hi(name) do\n  print(\"hello \" + name)\nend\n", .{});
    _ = try ws.inspectDetailed(alloc, id, query_opts);

    var hov = try ws.hover(alloc, id, .{ .line = 3, .character = 5 }, query_opts);
    defer if (hov) |*h| h.deinit(alloc);
    try std.testing.expect(hov != null);
}
