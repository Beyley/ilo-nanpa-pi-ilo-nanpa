const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const math = @import("mach").math;
const math_helpers = @import("math_helpers.zig");
const zigimg = @import("zigimg");
const Atlas = @import("atlas.zig");
const Gfx = @import("gfx.zig");
const Renderer = @import("renderer.zig");
const Codepoint = @import("codepoint.zig").Codepoint;

pub const App = @This();

gfx: Gfx,
renderer: Renderer,

working_number: i64,

pub fn init(app: *App) !void {
    try core.init(.{
        .title = "ilo nanpa pi ilo nanpa",
        .is_app = true,
        .power_preference = .low_power,
    });

    app.* = .{
        .gfx = try Gfx.init(),
        .renderer = undefined,
        .working_number = 0,
    };
    app.renderer = try Renderer.init(core.allocator, &app.*.gfx);
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    app.gfx.deinit();
    app.renderer.deinit();
}

pub fn button(loc: Renderer.Bounds, interact_loc: ?math.Vec2) bool {
    if (interact_loc) |mouse_loc| {
        const bottom_right = loc.pos.add(&loc.size);

        //If the event was within the button, return true for a hit
        if (mouse_loc.x() > loc.pos.x() and mouse_loc.y() > loc.pos.y() and mouse_loc.x() < bottom_right.x() and mouse_loc.y() < bottom_right.y()) {
            return true;
        }
    }

    return false;
}

pub fn update(app: *App) !bool {
    //Set to null when theres no interact event this frame, set to a position when an interact event happens
    var interact_loc: ?math.Vec2 = null;

    var event_iter = core.pollEvents();
    while (event_iter.next()) |event| {
        switch (event) {
            .close => return true,
            .framebuffer_resize => |size| try app.gfx.updateProjectionMatrix(size),
            //Whenever we get a mouse release event, set the interact location to the release position
            .mouse_release => |release| interact_loc = math.vec2(@floatCast(release.pos.x), @floatCast(release.pos.y)),
            else => {},
        }
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);

    try app.renderer.begin();

    const number_size = 128;

    {
        var text_writer = app.renderer.writer(math.vec2(10, 10), math.vec4(1, 1, 1, 1), number_size);

        try text_writer.writeAll(&.{ .nanpa, .colon });
        // text_writer.curr_pos = text_writer.curr_pos.add(&math.vec2(30, 0));

        try text_writer.writeNumber(app.working_number, .{});
        // try text_writer.writeNumber(app.working_number, .{ .four_type = .po, .san = true, .likujo = true });
    }

    const reset_button_location = try app.renderer.renderButton(
        math.vec2(10, 10 + number_size),
        math.vec2(0, 0),
        math.vec4(0.5, 0.5, 0.5, 1),
        &.{ .o, .tawa, .e, .nanpa, .tawa, .ala },
        64,
        .tl,
    );
    if (button(reset_button_location, interact_loc)) {
        app.working_number = 0;
    }

    const en_text = try app.renderer.writeText(math.vec2(10, number_size + reset_button_location.size.y() + 10 + 10 + Renderer.button_text_padding), 64, &.{ .en, .colon });

    var last_button_location: Renderer.Bounds = .{ .pos = math.vec2(en_text.size.x(), 10 + number_size + reset_button_location.size.y() + 10), .size = math.vec2(0, 0) };

    inline for (&.{
        .{ &.{.ale}, 100 },
        .{ &.{.mute}, 20 },
        .{ &.{.luka}, 5 },
        .{ &.{.tu}, 2 },
        .{ &.{.wan}, 1 },
    }) |item| {
        last_button_location = try app.renderer.renderButton(
            last_button_location.pos.add(&math.vec2(last_button_location.size.x() + 10, 0)),
            math.vec2(0, 0),
            math.vec4(0.5, 0.5, 0.5, 1),
            item[0],
            64,
            .tl,
        );
        if (button(last_button_location, interact_loc)) {
            app.working_number += item[1];
        }
    }

    const weka_text = try app.renderer.writeText(
        math.vec2(10, last_button_location.pos.y() + last_button_location.size.y() + 10 + Renderer.button_text_padding),
        64,
        &.{ .weka, .colon },
    );

    last_button_location = .{ .pos = math.vec2(weka_text.size.x(), last_button_location.pos.y() + last_button_location.size.y() + 10), .size = math.vec2(0, 0) };

    inline for (&.{
        .{ &.{.ale}, -100 },
        .{ &.{.mute}, -20 },
        .{ &.{.luka}, -5 },
        .{ &.{.tu}, -2 },
        .{ &.{.wan}, -1 },
    }) |item| {
        last_button_location = try app.renderer.renderButton(
            last_button_location.pos.add(&math.vec2(last_button_location.size.x() + 10, 0)),
            math.vec2(0, 0),
            math.vec4(0.5, 0.5, 0.5, 1),
            item[0],
            64,
            .tl,
        );
        if (button(last_button_location, interact_loc)) {
            app.working_number += item[1];
        }
    }

    try app.renderer.end();
    try app.renderer.draw(pass);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    return false;
}
