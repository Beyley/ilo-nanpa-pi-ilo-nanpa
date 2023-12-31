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

pub fn init(app: *App) !void {
    try core.init(.{
        .title = "ilo nanpa pi ilo nanpa",
        .is_app = true,
        .power_preference = .low_power,
    });

    app.* = .{
        .gfx = try Gfx.init(),
        .renderer = undefined,
    };
    app.renderer = try Renderer.init(core.allocator, &app.*.gfx);
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    app.gfx.deinit();
    app.renderer.deinit();
}

pub fn update(app: *App) !bool {
    var event_iter = core.pollEvents();
    while (event_iter.next()) |event| {
        switch (event) {
            .close => return true,
            .framebuffer_resize => |size| try app.gfx.updateProjectionMatrix(size),
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
    // pass.setPipeline(app.gfx.font_pipeline);
    // pass.setVertexBuffer(0, app.gfx.vertex_buffer, 0, @sizeOf(Gfx.FontVertex) * 6);
    // pass.setBindGroup(0, app.gfx.projection_matrix_bind_group, null);
    // pass.setBindGroup(1, app.gfx.font_texture_bind_group, null);
    // pass.draw(6, 1, 0, 0);

    const scale = 4;
    const scale_vec = math.vec2(scale, scale);

    try app.renderer.begin();

    var x: f32 = 0;
    const codepoints: []const Codepoint = &.{ .kijetesantakalu, .tonsi, .li, .lanpan, .e, .soko };
    inline for (codepoints) |codepoint| {
        try app.renderer.reserveTexQuad(codepoint, math.vec2(x, 0), scale_vec, math.vec4(1, 1, 1, 1));
        x += app.gfx.getTexSizeFromAtlas(@intFromEnum(codepoint)).x() * scale;
    }

    // try app.renderer.reserveTexQuad(0xF1980, math.vec2(0, 0), scale_vec, math.vec4(1, 1, 1, 1));
    // try app.renderer.reserveTexQuad(0xF197E, math.vec2(70 * scale, 0), scale_vec, math.vec4(1, 1, 1, 1));
    // try app.renderer.reserveTexQuad(0xF1927, math.vec2(140 * scale, 0), scale_vec, math.vec4(1, 1, 1, 1));
    // try app.renderer.reserveTexQuad(0xF1985, math.vec2(200 * scale, 0), scale_vec, math.vec4(1, 1, 1, 1));
    // try app.renderer.reserveTexQuad(0xF1909, math.vec2(270 * scale, 0), scale_vec, math.vec4(1, 1, 1, 1));
    // try app.renderer.reserveTexQuad(0xF1981, math.vec2(340 * scale, 0), scale_vec, math.vec4(1, 1, 1, 1));
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
