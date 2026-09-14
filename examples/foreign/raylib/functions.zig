const revo = @import("revo");
const rl = @import("raylib");
const std = @import("std");

const HostBinding = revo.HostBinding;
const HostResult = revo.std_lib.HostResult;
const Data = revo.Data;
const VM = revo.VM;

// -- helpers --

fn toZstr(vm: *VM, id: revo.StringID) ?[:0]const u8 {
    const bytes = vm.stringValue(id);
    const buf = vm.runtime.alloc.alloc(u8, bytes.len + 1) catch return null;
    @memcpy(buf[0..bytes.len], bytes);
    buf[bytes.len] = 0;
    return buf[0..bytes.len :0];
}

fn freeZstr(vm: *VM, z: [:0]const u8) void {
    vm.runtime.alloc.free(z.ptr[0 .. z.len + 1]);
}

fn colorArg(args: []const Data, start: usize) ?rl.Color {
    if (args.len < start + 3) return null;
    const r: u8 = @intFromFloat(args[start].asNum() orelse return null);
    const g: u8 = @intFromFloat(args[start + 1].asNum() orelse return null);
    const b: u8 = @intFromFloat(args[start + 2].asNum() orelse return null);
    const a: u8 = if (start + 3 < args.len)
        @intFromFloat(args[start + 3].asNum() orelse 255)
    else
        255;
    return rl.Color{ .r = r, .g = g, .b = b, .a = a };
}

// -- core --

fn initWindow(args: []const Data, vm: *VM) anyerror!HostResult {
    const w: i32 = @intFromFloat(try args[0].asNumber());
    const h: i32 = @intFromFloat(try args[1].asNumber());
    const title_id = args[2].asString() orelse return HostResult.errType(2, "string", "other");
    const title = toZstr(vm, title_id) orelse return HostResult.other("oom");
    defer freeZstr(vm, title);
    rl.initWindow(w, h, title);
    return .data(Data.new.nil());
}

fn closeWindow(_: []const Data, _: *VM) anyerror!HostResult {
    rl.closeWindow();
    return .data(Data.new.nil());
}

fn windowShouldClose(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.boolean(rl.windowShouldClose()));
}

fn setTargetFPS(args: []const Data, _: *VM) anyerror!HostResult {
    const fps: i32 = @intFromFloat(try args[0].asNumber());
    rl.setTargetFPS(fps);
    return .data(Data.new.nil());
}

fn getFPS(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(rl.getFPS()));
}

fn getFrameTime(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(rl.getFrameTime()));
}

fn getScreenWidth(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(rl.getScreenWidth()));
}

fn getScreenHeight(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(rl.getScreenHeight()));
}

// -- drawing --

fn beginDrawing(_: []const Data, _: *VM) anyerror!HostResult {
    rl.beginDrawing();
    return .data(Data.new.nil());
}

fn endDrawing(_: []const Data, _: *VM) anyerror!HostResult {
    rl.endDrawing();
    return .data(Data.new.nil());
}

fn clearBackground(args: []const Data, _: *VM) anyerror!HostResult {
    const c = colorArg(args, 0) orelse rl.Color.white;
    rl.clearBackground(c);
    return .data(Data.new.nil());
}

fn drawText(args: []const Data, vm: *VM) anyerror!HostResult {
    const text_id = args[0].asString() orelse return HostResult.errType(0, "string", "other");
    const text = toZstr(vm, text_id) orelse return HostResult.other("oom");
    defer freeZstr(vm, text);

    const x: i32 = @intFromFloat(try args[1].asNumber());
    const y: i32 = @intFromFloat(try args[2].asNumber());
    const size: i32 = @intFromFloat(try args[3].asNumber());
    const c = colorArg(args, 4) orelse rl.Color.white;
    rl.drawText(text, x, y, size, c);
    return .data(Data.new.nil());
}

fn drawRectangle(args: []const Data, _: *VM) anyerror!HostResult {
    const x: i32 = @intFromFloat(try args[0].asNumber());
    const y: i32 = @intFromFloat(try args[1].asNumber());
    const w: i32 = @intFromFloat(try args[2].asNumber());
    const h: i32 = @intFromFloat(try args[3].asNumber());
    const c = colorArg(args, 4) orelse rl.Color.white;
    rl.drawRectangle(x, y, w, h, c);
    return .data(Data.new.nil());
}

fn drawCircle(args: []const Data, _: *VM) anyerror!HostResult {
    const cx: i32 = @intFromFloat(try args[0].asNumber());
    const cy: i32 = @intFromFloat(try args[1].asNumber());
    const r: f32 = @floatCast(try args[2].asNumber());
    const c = colorArg(args, 3) orelse rl.Color.white;
    rl.drawCircle(cx, cy, r, c);
    return .data(Data.new.nil());
}

fn drawLine(args: []const Data, _: *VM) anyerror!HostResult {
    const x1: i32 = @intFromFloat(try args[0].asNumber());
    const y1: i32 = @intFromFloat(try args[1].asNumber());
    const x2: i32 = @intFromFloat(try args[2].asNumber());
    const y2: i32 = @intFromFloat(try args[3].asNumber());
    const thick: f32 = @floatCast(try args[4].asNumber());

    const c = colorArg(args, 5) orelse rl.Color.white;
    rl.drawLineEx(.{ .x = @floatFromInt(x1), .y = @floatFromInt(y1) }, .{ .x = @floatFromInt(x2), .y = @floatFromInt(y2) }, thick, c);
    return .data(Data.new.nil());
}

fn drawFPS(args: []const Data, _: *VM) anyerror!HostResult {
    const x: i32 = @intFromFloat(try args[0].asNumber());
    const y: i32 = @intFromFloat(try args[1].asNumber());
    rl.drawFPS(x, y);
    return .data(Data.new.nil());
}

// -- input --

fn isKeyPressed(args: []const Data, _: *VM) anyerror!HostResult {
    const key: i32 = @intFromFloat(try args[0].asNumber());
    return .data(Data.new.boolean(rl.isKeyPressed(@enumFromInt(key))));
}

fn isKeyDown(args: []const Data, _: *VM) anyerror!HostResult {
    const key: i32 = @intFromFloat(try args[0].asNumber());
    return .data(Data.new.boolean(rl.isKeyDown(@enumFromInt(key))));
}

fn isKeyReleased(args: []const Data, _: *VM) anyerror!HostResult {
    const key: i32 = @intFromFloat(try args[0].asNumber());
    return .data(Data.new.boolean(rl.isKeyReleased(@enumFromInt(key))));
}

fn getKeyPressed(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(@intFromEnum(rl.getKeyPressed())));
}

fn isMouseButtonPressed(args: []const Data, _: *VM) anyerror!HostResult {
    const btn: i32 = @intFromFloat(try args[0].asNumber());
    return .data(Data.new.boolean(rl.isMouseButtonPressed(@enumFromInt(btn))));
}

fn isMouseButtonDown(args: []const Data, _: *VM) anyerror!HostResult {
    const btn: i32 = @intFromFloat(try args[0].asNumber());
    return .data(Data.new.boolean(rl.isMouseButtonDown(@enumFromInt(btn))));
}

fn getMouseX(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(rl.getMouseX()));
}

fn getMouseY(_: []const Data, _: *VM) anyerror!HostResult {
    return .data(Data.new.num(rl.getMouseY()));
}

// -- text --

fn measureText(args: []const Data, vm: *VM) anyerror!HostResult {
    const text_id = args[0].asString() orelse return HostResult.errType(0, "string", "other");
    const text = toZstr(vm, text_id) orelse return HostResult.other("oom");
    defer freeZstr(vm, text);
    const size: i32 = @intFromFloat(try args[1].asNumber());
    return .data(Data.new.num(rl.measureText(text, size)));
}

// -- export --

pub export const revo_native_bindings = [_]HostBinding{
    // core
    .{ .name = "init_window", .fn_ptr = @ptrCast(&initWindow), .arity = 3, .variadic = false },
    .{ .name = "close_window", .fn_ptr = @ptrCast(&closeWindow), .arity = 0, .variadic = false },
    .{ .name = "window_should_close", .fn_ptr = @ptrCast(&windowShouldClose), .arity = 0, .variadic = false },
    .{ .name = "set_target_fps", .fn_ptr = @ptrCast(&setTargetFPS), .arity = 1, .variadic = false },
    .{ .name = "get_fps", .fn_ptr = @ptrCast(&getFPS), .arity = 0, .variadic = false },
    .{ .name = "get_frame_time", .fn_ptr = @ptrCast(&getFrameTime), .arity = 0, .variadic = false },
    .{ .name = "get_screen_width", .fn_ptr = @ptrCast(&getScreenWidth), .arity = 0, .variadic = false },
    .{ .name = "get_screen_height", .fn_ptr = @ptrCast(&getScreenHeight), .arity = 0, .variadic = false },
    // drawing
    .{ .name = "begin_drawing", .fn_ptr = @ptrCast(&beginDrawing), .arity = 0, .variadic = false },
    .{ .name = "end_drawing", .fn_ptr = @ptrCast(&endDrawing), .arity = 0, .variadic = false },
    .{ .name = "clear_background", .fn_ptr = @ptrCast(&clearBackground), .arity = 3, .variadic = true },
    .{ .name = "draw_text", .fn_ptr = @ptrCast(&drawText), .arity = 4, .variadic = true },
    .{ .name = "draw_rectangle", .fn_ptr = @ptrCast(&drawRectangle), .arity = 7, .variadic = false },
    .{ .name = "draw_circle", .fn_ptr = @ptrCast(&drawCircle), .arity = 6, .variadic = false },
    .{ .name = "draw_line", .fn_ptr = @ptrCast(&drawLine), .arity = 8, .variadic = false },
    .{ .name = "draw_fps", .fn_ptr = @ptrCast(&drawFPS), .arity = 2, .variadic = false },
    // input
    .{ .name = "is_key_pressed", .fn_ptr = @ptrCast(&isKeyPressed), .arity = 1, .variadic = false },
    .{ .name = "is_key_down", .fn_ptr = @ptrCast(&isKeyDown), .arity = 1, .variadic = false },
    .{ .name = "is_key_released", .fn_ptr = @ptrCast(&isKeyReleased), .arity = 1, .variadic = false },
    .{ .name = "get_key_pressed", .fn_ptr = @ptrCast(&getKeyPressed), .arity = 0, .variadic = false },
    .{ .name = "is_mouse_button_pressed", .fn_ptr = @ptrCast(&isMouseButtonPressed), .arity = 1, .variadic = false },
    .{ .name = "is_mouse_button_down", .fn_ptr = @ptrCast(&isMouseButtonDown), .arity = 1, .variadic = false },
    .{ .name = "get_mouse_x", .fn_ptr = @ptrCast(&getMouseX), .arity = 0, .variadic = false },
    .{ .name = "get_mouse_y", .fn_ptr = @ptrCast(&getMouseY), .arity = 0, .variadic = false },
    // text
    .{ .name = "measure_text", .fn_ptr = @ptrCast(&measureText), .arity = 2, .variadic = false },
    std.mem.zeroes(HostBinding),
};
