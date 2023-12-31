const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const math = @import("mach").math;
const math_helpers = @import("math_helpers.zig");
const zigimg = @import("zigimg");
const Atlas = @import("atlas.zig");
const Gfx = @import("gfx.zig");

pub const App = @This();

gfx: Gfx,

pub fn init(app: *App) !void {
    try core.init(.{
        .title = "ilo nanpa pi ilo nanpa",
        .is_app = true,
        .power_preference = .low_power,
    });

    app.* = .{
        .gfx = try Gfx.init(),
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    app.gfx.font_pipeline.release();
    app.gfx.font_texture_bind_group.release();
    app.gfx.vertex_buffer.release();
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
    pass.setPipeline(app.gfx.font_pipeline);
    pass.setVertexBuffer(0, app.gfx.vertex_buffer, 0, @sizeOf(Gfx.FontVertex) * 6);
    pass.setBindGroup(0, app.gfx.projection_matrix_bind_group, null);
    pass.setBindGroup(1, app.gfx.font_texture_bind_group, null);
    pass.draw(6, 1, 0, 0);
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
