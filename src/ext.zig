//!
//! stdlib-ish typed host functions for `.so` extensions
//!
//! shape:
//! ```zig
//! const revo = @import("revo");
//! const ext = revo.ext;
//!
//! const Impl = struct {
//!     pub fn add(vm: *ext.VM, a: ext.T.number, b: ext.T.number) !ext.HostResult {
//!         return .data(ext.Data.new.num(a + b));
//!     }
//!     pub fn greet(vm: *ext.VM, name: ext.T.string) !ext.HostResult {
//!         const bytes = ext.str(vm, name);
//!         const id = try vm.strings.own(bytes);
//!         return .data(ext.Data.new.str(id));
//!     }
//! };
//!
//! pub export const revo_bindings = ext.bindingsFor(Impl);
//! ```
//!
//! args here are runtime, full comptime type information is still .d.rv
//!

const std = @import("std");

const revo = @import("root.zig");
const std_lib = @import("std/root.zig");
const api = @import("std/api.zig");

pub const T = std_lib.T;
pub const TypeSpec = std_lib.TypeSpec;
pub const HostFunc = std_lib.HostFunc;
pub const HostFn = std_lib.HostFn;
pub const HostResult = std_lib.HostResult;
pub const VM = revo.VM;
pub const Data = revo.Data;

/// derive arity/param_types/unwrapping from a `fn (vm: *VM, typed args...) !HostResult` signature
/// , `T.Optional` params become optional with defaults
pub const def = std_lib.def;
/// explicit prefix types; this is where you do variadic tails
pub const define = std_lib.define;
pub const defineVariadic = std_lib.defineVariadic;
/// collect `pub fn`s of a struct into `[]api.Impl`, names are decl names
pub const impls = std_lib.impls;
/// checked float-to-int conversion, null when not a finite integral value
pub const numToInt = std_lib.numToInt;

/// max typed params per binding;
/// vm has a small-arg fast path (16)
/// so every checked arg stays out of the heap allocator
///
/// if you need more, you should use tables instead
pub const max_params = 16;

/// build a C-stable binding from a `def`-style `HostFunc`
///
/// `name` must be a comptime string (literal or decl name)
///
/// both carry a nul sentinel in the binary, which is what the host scans with `span`
/// trailing params at/after arity are marked omittable, so `T.Optional` must trail
pub fn binding(comptime name: [:0]const u8, comptime f: HostFunc) revo.functions.HostBinding {
    const HB = revo.functions.HostBinding;
    comptime {
        if (f.arity > max_params) @compileError("extension binding arity exceeds 16");
        if (f.param_types.len > max_params) @compileError("extension binding param_types exceeds 16");
    }
    var tags: [max_params]u8 = .{HB.end} ** max_params;
    comptime var i: usize = 0;
    inline for (f.param_types) |spec| {
        // through a value: `Type.variant.method()` would resolve
        // against the tag type instead of calling the union method
        tags[i] = spec.toTag() | (if (i >= f.arity) HB.optional else 0);
        i += 1;
    }
    return .{
        .name = name,
        .fn_ptr = @ptrCast(@alignCast(f.func)),
        .param_types = tags,
        .total_arity = if (f.variadic) HB.unbounded else @intCast(f.param_types.len),
    };
}

/// build a null-terminated `HostBinding` table from an explicit `[]api.Impl` list
///
/// plain structs need `bindingsFor`
pub fn bindings(comptime list: []const api.Impl) [list.len + 1]revo.functions.HostBinding {
    var out: [list.len + 1]revo.functions.HostBinding = undefined;
    inline for (list, 0..) |imp, i| {
        // decl names and string literals both have a null sentinel in the binary
        //
        // re derive sentinel slice from raw ptr
        const zname: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrCast(imp.name.ptr)));
        if (!std.mem.eql(u8, zname, imp.name)) {
            @compileError("extension binding name is not nul-terminated; use a string literal");
        }
        out[i] = binding(zname, imp.f);
    }
    out[list.len] = std.mem.zeroes(revo.functions.HostBinding);
    return out;
}

/// build a null-terminated `HostBinding` table from a stdlib-style
/// `Impl` struct: `pub export const revo_bindings =
/// ext.bindingsFor(Impl);`
pub fn bindingsFor(comptime S: type) [(impls(S).val.len) + 1]revo.functions.HostBinding {
    return bindings(impls(S).val);
}

// -- [helpers] ---------------------------------------------------------------
// prime area for addition contribs
// ----------------------------------------------------------------------------

/// borrowed bytes of a `T.string` arg; valid until the next GC sweep
///
/// copy it when holding across allocations
pub fn str(vm: *VM, s: T.string) []const u8 {
    return vm.stringValue(@intFromEnum(s));
}

/// nul-terminated copy of a `T.string` arg for C interop; free with `freeZstr`
pub fn zstr(vm: *VM, s: T.string) ![:0]const u8 {
    const bytes = str(vm, s);
    const buf = try vm.runtime.alloc.alloc(u8, bytes.len + 1);
    @memcpy(buf[0..bytes.len], bytes);
    buf[bytes.len] = 0;
    return buf[0..bytes.len :0];
}

pub fn freeZstr(vm: *VM, z: [:0]const u8) void {
    vm.runtime.alloc.free(z.ptr[0 .. z.len + 1]);
}

/// checked `T.number` (f64) to int conversion
/// , null when not a finite integral value representable in `I`
pub fn int(comptime I: type, n: T.number) ?I {
    return numToInt(I, n);
}

// -- [test] ------------------------------------------------------------------

test bindingsFor {
    const HB = revo.functions.HostBinding;
    const S = struct {
        pub fn add(vm: *VM, a: T.number, b: T.number) !HostResult {
            _ = vm;
            return .data(Data.new.num(a + b));
        }
        pub fn with_opt(vm: *VM, a: T.number, b: T.Optional(.number, 5)) !HostResult {
            _ = vm;
            return .data(Data.new.num(a + b.value));
        }
        pub fn greet(vm: *VM, name: T.string) !HostResult {
            _ = vm;
            _ = name;
            return .data(Data.new.nil());
        }
    };
    const table = comptime bindingsFor(S);
    try std.testing.expectEqual(@as(usize, 4), table.len);

    const num_spec: TypeSpec = .number;
    const str_spec: TypeSpec = .string;

    try std.testing.expectEqualStrings("add", std.mem.span(table[0].name));
    try std.testing.expectEqual(@as(u8, 2), table[0].total_arity);
    try std.testing.expectEqual(num_spec.toTag(), table[0].param_types[0]);
    try std.testing.expectEqual(num_spec.toTag(), table[0].param_types[1]);
    try std.testing.expectEqual(HB.end, table[0].param_types[2]);

    try std.testing.expectEqualStrings("with_opt", std.mem.span(table[1].name));
    try std.testing.expectEqual(@as(u8, 2), table[1].total_arity);
    try std.testing.expectEqual(num_spec.toTag(), table[1].param_types[0]);
    try std.testing.expectEqual(num_spec.toTag() | HB.optional, table[1].param_types[1]);
    try std.testing.expectEqual(HB.end, table[1].param_types[2]);

    try std.testing.expectEqualStrings("greet", std.mem.span(table[2].name));
    try std.testing.expectEqual(@as(u8, 1), table[2].total_arity);
    try std.testing.expectEqual(str_spec.toTag(), table[2].param_types[0]);
    try std.testing.expectEqual(HB.end, table[2].param_types[1]);

    // null terminator
    const term_name: ?[*:0]const u8 = @ptrCast(table[3].name);
    try std.testing.expect(term_name == null);
}

test bindings {
    const HB = revo.functions.HostBinding;
    const shout = struct {
        fn f(args: []const Data, vm: *VM) anyerror!HostResult {
            _ = args;
            _ = vm;
            return .data(Data.new.num(1));
        }
    }.f;
    const bound = comptime bindings(&.{
        .{ .name = "shout", .f = defineVariadic(&.{.string}, shout) },
    });
    try std.testing.expectEqual(@as(usize, 2), bound.len);
    try std.testing.expectEqualStrings("shout", std.mem.span(bound[0].name));
    try std.testing.expectEqual(HB.unbounded, bound[0].total_arity);
    const str_spec: TypeSpec = .string;
    try std.testing.expectEqual(str_spec.toTag(), bound[0].param_types[0]);
    try std.testing.expectEqual(HB.end, bound[0].param_types[1]);
}
