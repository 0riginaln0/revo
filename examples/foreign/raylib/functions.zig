//! also see ./raylib.d.rv

const revo = @import("revo");
const rl = @import("raylib");

const ext = revo.ext;
const T = ext.T;
const VM = ext.VM;
const Data = ext.Data;
const HostResult = ext.HostResult;

const Alpha = T.Optional(.number, 255);

// -- helpers --

fn color(r: T.number, g: T.number, b: T.number, a: Alpha) rl.Color {
    return .{
        .r = @intFromFloat(r),
        .g = @intFromFloat(g),
        .b = @intFromFloat(b),
        .a = @intFromFloat(a.value),
    };
}

const Impl = struct {
    // -- core --

    pub fn init_window(vm: *VM, w: T.number, h: T.number, title: T.string) !HostResult {
        const name = try ext.zstr(vm, title);
        defer ext.freeZstr(vm, name);
        rl.initWindow(@intFromFloat(w), @intFromFloat(h), name);
        return .data(Data.new.nil());
    }

    pub fn close_window(vm: *VM) !HostResult {
        _ = vm;
        rl.closeWindow();
        return .data(Data.new.nil());
    }

    pub fn window_should_close(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.boolean(rl.windowShouldClose()));
    }

    pub fn set_target_fps(vm: *VM, fps: T.number) !HostResult {
        _ = vm;
        rl.setTargetFPS(@intFromFloat(fps));
        return .data(Data.new.nil());
    }

    pub fn get_fps(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(rl.getFPS()));
    }

    pub fn get_frame_time(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(rl.getFrameTime()));
    }

    pub fn get_screen_width(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(rl.getScreenWidth()));
    }

    pub fn get_screen_height(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(rl.getScreenHeight()));
    }

    // -- drawing --

    pub fn begin_drawing(vm: *VM) !HostResult {
        _ = vm;
        rl.beginDrawing();
        return .data(Data.new.nil());
    }

    pub fn end_drawing(vm: *VM) !HostResult {
        _ = vm;
        rl.endDrawing();
        return .data(Data.new.nil());
    }

    pub fn clear_background(vm: *VM, r: T.number, g: T.number, b: T.number, a: Alpha) !HostResult {
        _ = vm;
        rl.clearBackground(color(r, g, b, a));
        return .data(Data.new.nil());
    }

    pub fn draw_text(
        vm: *VM,
        text: T.string,
        x: T.number,
        y: T.number,
        size: T.number,
        r: T.number,
        g: T.number,
        b: T.number,
        a: Alpha,
    ) !HostResult {
        const t = try ext.zstr(vm, text);
        defer ext.freeZstr(vm, t);
        rl.drawText(t, @intFromFloat(x), @intFromFloat(y), @intFromFloat(size), color(r, g, b, a));
        return .data(Data.new.nil());
    }

    pub fn draw_rectangle(
        vm: *VM,
        x: T.number,
        y: T.number,
        w: T.number,
        h: T.number,
        r: T.number,
        g: T.number,
        b: T.number,
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
        return .data(Data.new.nil());
    }

    pub fn draw_circle(
        vm: *VM,
        cx: T.number,
        cy: T.number,
        radius: T.number,
        r: T.number,
        g: T.number,
        b: T.number,
        a: Alpha,
    ) !HostResult {
        _ = vm;
        rl.drawCircle(@intFromFloat(cx), @intFromFloat(cy), @floatCast(radius), color(r, g, b, a));
        return .data(Data.new.nil());
    }

    pub fn draw_line(
        vm: *VM,
        x1: T.number,
        y1: T.number,
        x2: T.number,
        y2: T.number,
        thick: T.number,
        r: T.number,
        g: T.number,
        b: T.number,
        a: Alpha,
    ) !HostResult {
        _ = vm;
        rl.drawLineEx(
            .{ .x = @floatCast(x1), .y = @floatCast(y1) },
            .{ .x = @floatCast(x2), .y = @floatCast(y2) },
            @floatCast(thick),
            color(r, g, b, a),
        );
        return .data(Data.new.nil());
    }

    pub fn draw_fps(vm: *VM, x: T.number, y: T.number) !HostResult {
        _ = vm;
        rl.drawFPS(@intFromFloat(x), @intFromFloat(y));
        return .data(Data.new.nil());
    }

    // -- input --

    pub fn is_key_pressed(vm: *VM, key: T.number) !HostResult {
        _ = vm;
        return .data(Data.new.boolean(rl.isKeyPressed(@enumFromInt(@as(i32, @intFromFloat(key))))));
    }

    pub fn is_key_down(vm: *VM, key: T.number) !HostResult {
        _ = vm;
        return .data(Data.new.boolean(rl.isKeyDown(@enumFromInt(@as(i32, @intFromFloat(key))))));
    }

    pub fn is_key_released(vm: *VM, key: T.number) !HostResult {
        _ = vm;
        return .data(Data.new.boolean(rl.isKeyReleased(@enumFromInt(@as(i32, @intFromFloat(key))))));
    }

    pub fn get_key_pressed(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(@intFromEnum(rl.getKeyPressed())));
    }

    pub fn is_mouse_button_pressed(vm: *VM, btn: T.number) !HostResult {
        _ = vm;
        return .data(Data.new.boolean(rl.isMouseButtonPressed(@enumFromInt(@as(i32, @intFromFloat(btn))))));
    }

    pub fn is_mouse_button_down(vm: *VM, btn: T.number) !HostResult {
        _ = vm;
        return .data(Data.new.boolean(rl.isMouseButtonDown(@enumFromInt(@as(i32, @intFromFloat(btn))))));
    }

    pub fn get_mouse_x(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(rl.getMouseX()));
    }

    pub fn get_mouse_y(vm: *VM) !HostResult {
        _ = vm;
        return .data(Data.new.num(rl.getMouseY()));
    }

    // -- text --

    pub fn measure_text(vm: *VM, text: T.string, size: T.number) !HostResult {
        const t = try ext.zstr(vm, text);
        defer ext.freeZstr(vm, t);
        return .data(Data.new.num(rl.measureText(t, @intFromFloat(size))));
    }
};

pub export const revo_bindings = ext.bindingsFor(Impl);
