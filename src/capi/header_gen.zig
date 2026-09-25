//
// auto-generate revo.h from callconv(.c) exports
//
const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;

const template = @embedFile("revo.h.in");

/// each module adds the declarations for one marker in the template
const Module = struct {
    src: [:0]const u8, // @embedFile is already null-terminated
    prefix: []const u8, // only exports with this prefix are emitted
    marker: []const u8,
};

const modules = [_]Module{
    .{ .src = @embedFile("exports.zig"), .prefix = "revo_", .marker = "// @@REVO_DECLS@@" },
    .{ .src = @embedFile("embed.zig"), .prefix = "erevo_", .marker = "// @@EREVO_DECLS@@" },
};

const version_marker = "@@REVO_VERSION@@";

const c_types = std.StaticStringMap([]const u8).initComptime(.{
    .{ "u64", "uint64_t" },
    .{ "u8", "uint8_t" },
    .{ "u16", "uint16_t" },
    .{ "u32", "uint32_t" },
    .{ "i32", "int32_t" },
    .{ "i64", "int64_t" },
    .{ "f64", "double" },
    .{ "usize", "size_t" },
    .{ "c_int", "int" },
    .{ "c_char", "char" },
    .{ "void", "void" },
    .{ "bool", "bool" },
    .{ "*anyopaque", "void*" },
    .{ "?*anyopaque", "void*" },
    .{ "*constanyopaque", "const void*" },
    .{ "[*:0]constu8", "const char*" },
    .{ "[*:0]u8", "char*" },
    .{ "[*]constu8", "const char*" },
    .{ "[*]u8", "char*" },
    .{ "?[*]constu8", "const char*" },
    .{ "?[*]u8", "char*" },
    .{ "?*ErevoVM", "ErevoVM*" },
    .{ "*ErevoVM", "ErevoVM*" },
    .{ "?*ErevoProgram", "ErevoProgram*" },
    .{ "*ErevoProgram", "ErevoProgram*" },
    .{ "?*ErevoValue", "RevoValue*" },
    .{ "*ErevoValue", "RevoValue*" },
    .{ "Value", "RevoValue" },
    .{ "*Value", "RevoValue*" },
    .{ "*constValue", "const RevoValue*" },
    .{ "?*Value", "RevoValue*" },
    .{ "?*constValue", "const RevoValue*" },
    .{ "[*]constValue", "const RevoValue*" },
    .{ "[*]Value", "RevoValue*" },
    .{ "?[*]constValue", "const RevoValue*" },
    .{ "ErevoValue", "RevoValue" },
    .{ "ErevoVM", "ErevoVM" },
    .{ "ErevoProgram", "ErevoProgram" },
});

/// builds revo.h
/// caller owns the result
pub fn data(gpa: Allocator, version: []const u8) ![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    if (std.mem.indexOf(u8, template, version_marker) == null)
        return error.VersionMarkerNotFound;

    var out: []const u8 = template;
    for (modules) |m| {
        if (std.mem.indexOf(u8, out, m.marker) == null) {
            std.debug.print("revo.h: marker '{s}' not found in template\n", .{m.marker});
            return error.MarkerNotFound;
        }

        const decls = try renderModule(arena, m);
        out = try std.mem.replaceOwned(u8, arena, out, m.marker, decls);
        if (std.mem.indexOf(u8, out, m.marker) != null) return error.MarkerNotReplaced;
    }
    out = try std.mem.replaceOwned(u8, arena, out, version_marker, version);
    return gpa.dupe(u8, out);
}

/// emits every exported `callconv(.c)` fn with the module's prefix, in source order
/// (so you control grouping by ordering the zig source)
fn renderModule(arena: Allocator, m: Module) ![]const u8 {
    var ast = try Ast.parse(arena, m.src, .zig);
    defer ast.deinit(arena);
    if (ast.errors.len > 0) {
        for (ast.errors) |e| {
            const loc = ast.tokenLocation(0, e.token);
            std.debug.print("revo.h: parse error in {s} prefix module at line {d}:{d}: {s}\n", .{
                m.prefix, loc.line + 1, loc.column + 1, @tagName(e.tag),
            });
        }
        return error.ParseError;
    }

    var out: std.ArrayList(u8) = .empty;
    var seen = std.StringHashMap(void).init(arena);

    for (ast.rootDecls()) |node| {
        var buf: [1]Ast.Node.Index = undefined;
        // null for anything that isn't a fn, so no tag switch needed
        const proto = ast.fullFnProto(&buf, node) orelse continue;

        const conv = proto.ast.callconv_expr.unwrap() orelse continue;
        if (!std.mem.eql(u8, ast.getNodeSource(conv), ".c")) continue;

        const is_export = if (proto.extern_export_inline_token) |tok|
            ast.tokenTag(tok) == .keyword_export
        else
            false;

        const name = ast.tokenSlice(proto.name_token orelse continue);
        const wanted = std.mem.startsWith(u8, name, m.prefix);

        if (!is_export) {
            if (wanted)
                std.debug.print("revo.h: '{s}' is callconv(.c) with prefix '{s}' but not exported; skipping\n", .{ name, m.prefix });
            continue;
        }
        if (!wanted) {
            continue;
        }

        if (seen.contains(name)) {
            std.debug.print("revo.h: duplicate export '{s}'\n", .{name});
            return error.DuplicateExport;
        }
        try seen.put(try arena.dupe(u8, name), {});

        try emitDocComments(arena, &out, &ast, node);
        try emitSignature(arena, &out, &ast, proto, name);
    }
    return out.items;
}

/// `///` lines are tokens sitting directly before the decl's first token
/// (firstToken already accounts for `pub` / `export` / `inline`)
fn emitDocComments(arena: Allocator, out: *std.ArrayList(u8), ast: *const Ast, node: Ast.Node.Index) !void {
    const tags = ast.tokens.items(.tag);
    const first = ast.firstToken(node);

    var start = first;
    while (start > 0 and tags[start - 1] == .doc_comment) start -= 1;
    if (start == first) return;

    if (out.items.len > 0) try out.append(arena, '\n'); // breathing room
    for (start..first) |t| {
        // `///` passes through as-is, valid c99 and doxygen-friendly
        const line = std.mem.trimEnd(u8, ast.tokenSlice(@intCast(t)), " \t\r");
        try out.appendSlice(arena, line);
        try out.append(arena, '\n');
    }
}

fn emitSignature(
    arena: Allocator,
    out: *std.ArrayList(u8),
    ast: *const Ast,
    proto: Ast.full.FnProto,
    name: []const u8,
) !void {
    const ret_src = if (proto.ast.return_type.unwrap()) |r| ast.getNodeSource(r) else "void";
    try out.appendSlice(arena, "REVO_API ");
    try out.appendSlice(arena, try cTypeCtx(ret_src, name, null));
    try out.append(arena, ' ');
    try out.appendSlice(arena, name);
    try out.append(arena, '(');

    var n: usize = 0;
    var it = proto.iterate(ast);
    while (it.next()) |p| : (n += 1) {
        if (p.anytype_ellipsis3 != null) {
            const tok = ast.tokenSlice(p.anytype_ellipsis3.?);
            std.debug.print("revo.h: '{s}': variadic/anytype param '{s}' cannot cross the c abi\n", .{ name, tok });
            return error.AnytypeParamInExport;
        }
        if (p.comptime_noalias != null and std.mem.eql(u8, ast.tokenSlice(p.comptime_noalias.?), "comptime")) {
            std.debug.print("revo.h: '{s}': comptime param cannot cross the c abi\n", .{name});
            return error.ComptimeParamInExport;
        }
        if (n > 0) try out.appendSlice(arena, ", ");

        const pname: ?[]const u8 = if (p.name_token) |t| ast.tokenSlice(t) else null;
        const ty_node = p.type_expr orelse {
            std.debug.print("revo.h: '{s}': anytype param cannot cross the c abi\n", .{name});
            return error.AnytypeParamInExport;
        };
        try out.appendSlice(arena, try cTypeCtx(ast.getNodeSource(ty_node), name, pname));
        if (pname) |pn| {
            try out.append(arena, ' ');
            try out.appendSlice(arena, pn);
        }
    }
    if (n == 0) try out.appendSlice(arena, "void");

    try out.appendSlice(arena, ");\n");
}

fn cTypeCtx(zig: []const u8, fn_name: []const u8, param_name: ?[]const u8) ![]const u8 {
    var tmp: [256]u8 = undefined;
    var len: usize = 0;
    const trimmed = std.mem.trim(u8, zig, " \t\r\n");
    for (trimmed) |c| switch (c) {
        ' ', '\t', '\r', '\n' => continue,
        else => {
            if (len >= tmp.len) break;
            tmp[len] = c;
            len += 1;
        },
    };
    const key = tmp[0..len];
    if (c_types.get(key)) |c| return c;
    // nullable in zig but plain pointers in c
    if (len > 1 and key[0] == '?') {
        if (c_types.get(key[1..])) |c| return c;
    }
    if (param_name) |pn| {
        std.debug.print("revo.h: no c mapping for zig type '{s}' (fn '{s}', param '{s}')\n", .{ trimmed, fn_name, pn });
    } else {
        std.debug.print("revo.h: no c mapping for zig return type '{s}' (fn '{s}')\n", .{ trimmed, fn_name });
    }
    return error.UnmappedType;
}
