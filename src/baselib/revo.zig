const Args = root.host.ArgTypes;

pub const Impl = struct {
    pub fn eval(vm: *VM, source: Args.string) !HostResult {
        const src = vm.stringValue(@intFromEnum(source));
        const res = revo.run.runModule(vm, "<eval>", src, true) catch {
            return .other("eval failed");
        };
        return switch (res) {
            .ok => HostResult.Ok(vm, vm.currentFiber().result),
            .err => |err| {
                const err_str = try vm.ownValueString(revo.lang.diagnostic.firstError(err.report).?);
                return HostResult.errValue(vm, err_str);
            },
        };
    }

    pub fn compile(vm: *VM, source: Args.string) !HostResult {
        const src = vm.stringValue(@intFromEnum(source));
        const result = try revo.lang.build(vm, .{ .text = src, .name = "<anon>" }, .{});
        switch (result) {
            .ok => |bytecode| {
                defer vm.runtime.alloc.free(bytecode.instructions);
                defer vm.runtime.alloc.free(bytecode.spans);
                const bc = try revo.bytecode.serialize(vm, bytecode, vm.runtime.alloc);
                defer vm.runtime.alloc.free(bc);
                const sid = try vm.strings.own(bc);
                return HostResult.Ok(vm, Value.new.str(sid));
            },
            .err => |err| switch (err) {
                .compile => |e| return HostResult.errValue(vm, try vm.ownValueString(revo.lang.diagnostic.firstError(e.report).?)),
                .expand => |e| return HostResult.errValue(vm, try vm.ownValueString(revo.lang.diagnostic.firstError(e.report).?)),
                .parse => |e| return HostResult.errValue(vm, try vm.ownValueString(revo.lang.diagnostic.firstError(e.report).?)),
                .semantic => |e| return HostResult.errValue(vm, try vm.ownValueString(revo.lang.diagnostic.firstError(e.report).?)),
            },
        }
    }

    pub fn version(vm: *VM) !HostResult {
        const v = @import("build_options").version;
        return if (@import("builtin").mode == .Debug)
            .data(try vm.ownValueString("revo #" ++ v))
        else
            .data(try vm.ownValueString("revo v" ++ v));
    }

    pub fn threads(vm: *VM) !HostResult {
        return .data(Value.new.num(vm.sched.thread_count));
    }
};

pub const impls: []const specs.Impl = root.host.impls(Impl).val ++ &[_]specs.Impl{
    .{ .name = "dofile", .f = if (@import("build_options").is_freestanding) root.host.defineStub(&.{.string}) else root.host.define(&.{.string}, dofile) },
};

test "native eval works" {
    try testing.topNumber(
        \\ const {_, res} = revo.eval("21*2")
        \\ res
    , 42);
}

test "revo.compile compiles source" {
    try testing.topAtom(
        \\ revo.compile("1 + 1")[0]
    , "ok");
}

/// > dofile(path: string) -> !any
/// reads the file, evaluates it as a module, gives you back its' return value
/// like eval but the source comes from a file, relative paths resolve
/// against the current module's directory like `import`, then cwd
pub fn dofile(args: []const Value, vm: *VM) !HostResult {
    if (args.len != 1) return .errArity(args.len, 1);

    const path = switch (args[0].tag()) {
        .string => vm.stringValue(args[0].asString().?),
        else => return .errType(0, "string", typeof(args[0], vm)),
    };

    // import-style resolution: ./mod.rv means "next to the script", not
    // "next to the cwd"; raw path is the fallback for repl/-e runs
    const resolved: ?[]const u8 = revo.resolveImportFile(
        vm.runtime.io,
        vm.runtime.alloc,
        path,
        vm.import_dir,
        vm.project_root,
        vm.package_path.items,
    ) catch null;
    defer if (resolved) |p| vm.runtime.alloc.free(p);
    const real_path = resolved orelse path;

    const source = std.Io.Dir.cwd().readFileAlloc(
        vm.runtime.io,
        real_path,
        vm.runtime.alloc,
        .limited(fs.max_read_size),
    ) catch |err| {
        const msg = try vm.ownValueString(@errorName(err));
        return HostResult.errValue(vm, msg);
    };
    defer vm.runtime.alloc.free(source);

    const res = revo.run.runModule(vm, real_path, source, false) catch {
        return .other("dofile failed");
    };

    return switch (res) {
        .ok => HostResult.Ok(vm, vm.currentFiber().result),
        .err => |err| {
            const err_str = try vm.ownValueString(revo.lang.diagnostic.firstError(err.report).?);
            return HostResult.errValue(vm, err_str);
        },
    };
}

test "revo.dofile returns the file's value" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "hi.rv", .data = "{x = 2}" });

    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dir_path);
    const file_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ dir_path, "hi.rv" });
    defer std.testing.allocator.free(file_path);

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\ const {{_, res}} = revo.dofile('{s}')
        \\ res.x
    , .{file_path});
    defer std.testing.allocator.free(source);

    try testing.topNumber(source, 2);
}

test "revo.dofile resolves relative paths against the module dir" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "dep.rv", .data = "\"from-dep\"" });

    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    try testing.topStringInDir(dir_path,
        \\ revo.dofile("./dep.rv")[1]
    , "from-dep");
}

const revo = @import("../root.zig");
const testing = revo.lang.test_helpers;
const std = @import("std");
const Value = revo.Value;
const VM = revo.VM;
const fs = @import("fs.zig");
const root = @import("root.zig");
const specs = @import("specs.zig");
const HostResult = root.host.HostResult;
const typeof = root.typeof;
