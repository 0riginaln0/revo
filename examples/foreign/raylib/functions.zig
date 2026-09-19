//! also see ./raylib.d.rv

const revo = @import("revo");
const rl = @import("raylib");

const extension = revo.extension;
const Args = extension.ArgTypes;
const VM = extension.VM;
const Value = extension.Value;
const HostResult = extension.HostResult;

const Alpha = Args.Optional(.number, 255);

// -- helpers --

fn color(r: Args.number, g: Args.number, b: Args.number, a: Alpha) rl.Color {
    return .{
        .r = @intFromFloat(r),
        .g = @intFromFloat(g),
        .b = @intFromFloat(b),
        .a = @intFromFloat(a.value),
    };
}

const Impl = struct {
    // -- core --

    pub fn init_window(vm: *VM, w: Args.number, h: Args.number, title: Args.string) !HostResult {
        const name = try extension.zstr(vm, title);
        defer extension.freeZstr(vm, name);
        rl.initWindow(@intFromFloat(w), @intFromFloat(h), name);
        return .data(Value.new.nil());
    }

    pub fn close_window(vm: *VM) !HostResult {
        _ = vm;
        rl.closeWindow();
        return .data(Value.new.nil());
    }

    pub fn window_should_close(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.boolean(rl.windowShouldClose()));
    }

    pub fn set_target_fps(vm: *VM, fps: Args.number) !HostResult {
        _ = vm;
        rl.setTargetFPS(@intFromFloat(fps));
        return .data(Value.new.nil());
    }

    pub fn get_fps(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(rl.getFPS()));
    }

    pub fn get_frame_time(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(rl.getFrameTime()));
    }

    pub fn get_screen_width(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(rl.getScreenWidth()));
    }

    pub fn get_screen_height(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(rl.getScreenHeight()));
    }

    // -- drawing --

    pub fn begin_drawing(vm: *VM) !HostResult {
        _ = vm;
        rl.beginDrawing();
        return .data(Value.new.nil());
    }

    pub fn end_drawing(vm: *VM) !HostResult {
        _ = vm;
        rl.endDrawing();
        return .data(Value.new.nil());
    }

    pub fn clear_background(vm: *VM, r: Args.number, g: Args.number, b: Args.number, a: Alpha) !HostResult {
        _ = vm;
        rl.clearBackground(color(r, g, b, a));
        return .data(Value.new.nil());
    }

    pub fn draw_text(
        vm: *VM,
        text: Args.string,
        x: Args.number,
        y: Args.number,
        size: Args.number,
        r: Args.number,
        g: Args.number,
        b: Args.number,
        a: Alpha,
    ) !HostResult {
        const t = try extension.zstr(vm, text);
        defer extension.freeZstr(vm, t);
        rl.drawText(t, @intFromFloat(x), @intFromFloat(y), @intFromFloat(size), color(r, g, b, a));
        return .data(Value.new.nil());
    }

    pub fn draw_rectangle(
        vm: *VM,
        x: Args.number,
        y: Args.number,
        w: Args.number,
        h: Args.number,
        r: Args.number,
        g: Args.number,
        b: Args.number,
        a: Alpha,
    ) !HostResult {
        _ = vm;
        rl.drawRectangle(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(w),
            @intFromFloat(h),
            color(r, g, b, a),
        );
        return .data(Value.new.nil());
    }

    pub fn draw_circle(
        vm: *VM,
        cx: Args.number,
        cy: Args.number,
        radius: Args.number,
        r: Args.number,
        g: Args.number,
        b: Args.number,
        a: Alpha,
    ) !HostResult {
        _ = vm;
        rl.drawCircle(@intFromFloat(cx), @intFromFloat(cy), @floatCast(radius), color(r, g, b, a));
        return .data(Value.new.nil());
    }

    pub fn draw_line(
        vm: *VM,
        x1: Args.number,
        y1: Args.number,
        x2: Args.number,
        y2: Args.number,
        thick: Args.number,
        r: Args.number,
        g: Args.number,
        b: Args.number,
        a: Alpha,
    ) !HostResult {
        _ = vm;
        rl.drawLineEx(
            .{ .x = @floatCast(x1), .y = @floatCast(y1) },
            .{ .x = @floatCast(x2), .y = @floatCast(y2) },
            @floatCast(thick),
            color(r, g, b, a),
        );
        return .data(Value.new.nil());
    }

    pub fn draw_fps(vm: *VM, x: Args.number, y: Args.number) !HostResult {
        _ = vm;
        rl.drawFPS(@intFromFloat(x), @intFromFloat(y));
        return .data(Value.new.nil());
    }

    // -- input --

    pub fn is_key_pressed(vm: *VM, key: Args.number) !HostResult {
        _ = vm;
        return .data(Value.new.boolean(rl.isKeyPressed(@enumFromInt(@as(i32, @intFromFloat(key))))));
    }

    pub fn is_key_down(vm: *VM, key: Args.number) !HostResult {
        _ = vm;
        return .data(Value.new.boolean(rl.isKeyDown(@enumFromInt(@as(i32, @intFromFloat(key))))));
    }

    pub fn is_key_released(vm: *VM, key: Args.number) !HostResult {
        _ = vm;
        return .data(Value.new.boolean(rl.isKeyReleased(@enumFromInt(@as(i32, @intFromFloat(key))))));
    }

    pub fn get_key_pressed(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(@intFromEnum(rl.getKeyPressed())));
    }

    pub fn is_mouse_button_pressed(vm: *VM, btn: Args.number) !HostResult {
        _ = vm;
        return .data(Value.new.boolean(rl.isMouseButtonPressed(@enumFromInt(@as(i32, @intFromFloat(btn))))));
    }

    pub fn is_mouse_button_down(vm: *VM, btn: Args.number) !HostResult {
        _ = vm;
        return .data(Value.new.boolean(rl.isMouseButtonDown(@enumFromInt(@as(i32, @intFromFloat(btn))))));
    }

    pub fn get_mouse_x(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(rl.getMouseX()));
    }

    pub fn get_mouse_y(vm: *VM) !HostResult {
        _ = vm;
        return .data(Value.new.num(rl.getMouseY()));
    }

    // -- text --

    pub fn measure_text(vm: *VM, text: Args.string, size: Args.number) !HostResult {
        const t = try extension.zstr(vm, text);
        defer extension.freeZstr(vm, t);
        return .data(Value.new.num(rl.measureText(t, @intFromFloat(size))));
    }
};

pub export const revo_native_bindings_ex = extension.bindingsFor(Impl);
