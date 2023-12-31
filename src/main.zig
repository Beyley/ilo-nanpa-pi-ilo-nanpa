const std = @import("std");
const core = @import("mach-core");
const basisu = @import("mach-basisu");
const gpu = core.gpu;
const math = @import("mach").math;
const math_helpers = @import("math_helpers.zig");
const zigimg = @import("zigimg");

pub const App = @This();

font_pipeline: *gpu.RenderPipeline,
font_texture_bind_group: *gpu.BindGroup,
projection_matrix_bind_group: *gpu.BindGroup,
projection_matrix_buffer: *gpu.Buffer,
vertex_buffer: *gpu.Buffer,

const FontVertex = extern struct {
    pos: math.Vec2,
    tex_coord: math.Vec2,
    col: math.Vec4,
};

pub fn init(app: *App) !void {
    try core.init(.{
        .required_features = &.{.texture_compression_bc},
        .size = .{ .width = 1920, .height = 1080 },
        .title = "ilo nanpa pi ilo nanpa",
        .is_app = true,
    });

    // //Init the basisu transcoder
    // basisu.init_transcoder();

    // //Init the image transcoder
    // var trans = try basisu.Transcoder.init(@embedFile("output.basis"));
    // defer trans.deinit();

    // var imageDescriptor = try trans.getImageLevelDescriptor(0, 0);

    // //Allocate the output buffer of the image
    // const buf = try core.allocator.alloc(u8, try trans.calcTranscodedSize(0, 0, .rgba32));
    // defer core.allocator.free(buf);

    //Try to transcode the image
    // try trans.transcode(buf, 0, 0, .rgba32, .{});

    var img_stream = zigimg.Image.Stream{ .const_buffer = .{ .pos = 0, .buffer = @embedFile("output.png") } };
    var image = try zigimg.png.load(&img_stream, core.allocator, .{ .temp_allocator = core.allocator });
    defer image.deinit();

    var tex = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
        .label = "sdf",
        .usage = .{ .copy_dst = true, .texture_binding = true },
        .size = .{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
        },
        .format = .rgba8_unorm,
        .view_formats = &.{},
    }));
    defer tex.release();

    switch (image.pixels) {
        .rgba32 => |pixels| {
            core.queue.writeTexture(
                &gpu.ImageCopyTexture{
                    .texture = tex,
                },
                &gpu.Texture.DataLayout{
                    .rows_per_image = @intCast(image.height),
                    .bytes_per_row = @intCast(4 * image.width),
                },
                &gpu.Extent3D{
                    .height = @intCast(image.height),
                    .width = @intCast(image.width),
                },
                pixels,
            );
        },
        else => {
            std.log.info("SHIT {s}", .{@tagName(image.pixels)});
        },
    }

    var tex_view = tex.createView(&gpu.TextureView.Descriptor{
        .format = .rgba8_unorm,
        .array_layer_count = 1,
        .dimension = .dimension_2d,
        .label = "sdf_view",
    });
    defer tex_view.release();

    var sampler = core.device.createSampler(&gpu.Sampler.Descriptor{
        .label = "sampler",
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .linear,
    });
    defer sampler.release();

    var projection_matrix_buffer = core.device.createBuffer(&gpu.Buffer.Descriptor{
        .label = "projection matrix",
        .size = @sizeOf(math.Mat4x4),
        .usage = .{
            .copy_dst = true,
            .uniform = true,
        },
    });
    defer projection_matrix_buffer.release();

    core.queue.writeBuffer(projection_matrix_buffer, 0, &[_]math.Mat4x4{math_helpers.orthographicOffCenter(0, 1920, 0, 1080, 0, 1).transpose()});

    var projection_matrix_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "projection matrix bind group layout",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, false, @sizeOf(math.Mat4x4)),
        },
    }));
    defer projection_matrix_bind_group_layout.release();

    var font_texture_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "font bind group layout",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.texture(0, .{ .fragment = true }, .float, .dimension_2d, false),
            gpu.BindGroupLayout.Entry.sampler(1, .{ .fragment = true }, .filtering),
        },
    }));
    defer font_texture_bind_group_layout.release();

    app.* = .{
        .vertex_buffer = blk: {
            var vertex_buffer = core.device.createBuffer(&gpu.Buffer.Descriptor{
                .label = "vertex buffer",
                .size = @sizeOf(FontVertex) * 6,
                .usage = .{
                    .vertex = true,
                    .copy_dst = true,
                },
            });
            const image_size = 64 * 32;
            core.queue.writeBuffer(vertex_buffer, 0, &[_]FontVertex{
                FontVertex{
                    .pos = math.vec2(0, 0),
                    .col = math.vec4(1, 1, 1, 1),
                    .tex_coord = math.vec2(0, 0),
                },
                FontVertex{
                    .pos = math.vec2(image_size, image_size),
                    .col = math.vec4(1, 1, 1, 1),
                    .tex_coord = math.vec2(1, 1),
                },
                FontVertex{
                    .pos = math.vec2(0, image_size),
                    .col = math.vec4(1, 1, 1, 1),
                    .tex_coord = math.vec2(0, 1),
                },
                FontVertex{
                    .pos = math.vec2(0, 0),
                    .col = math.vec4(1, 1, 1, 1),
                    .tex_coord = math.vec2(0, 0),
                },
                FontVertex{
                    .pos = math.vec2(image_size, image_size),
                    .col = math.vec4(1, 1, 1, 1),
                    .tex_coord = math.vec2(1, 1),
                },
                FontVertex{
                    .pos = math.vec2(image_size, 0),
                    .col = math.vec4(1, 1, 1, 1),
                    .tex_coord = math.vec2(1, 0),
                },
            });

            break :blk vertex_buffer;
        },
        .projection_matrix_buffer = projection_matrix_buffer,
        .projection_matrix_bind_group = blk: {
            break :blk core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
                .label = "projection matrix bind group",
                .layout = projection_matrix_bind_group_layout,
                .entries = &[_]gpu.BindGroup.Entry{
                    gpu.BindGroup.Entry.buffer(0, projection_matrix_buffer, 0, @sizeOf(math.Mat4x4)),
                },
            }));
        },
        .font_texture_bind_group = blk: {
            break :blk core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
                .label = "font bind group",
                .layout = font_texture_bind_group_layout,
                .entries = &[_]gpu.BindGroup.Entry{
                    gpu.BindGroup.Entry.textureView(0, tex_view),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                },
            }));
        },
        .font_pipeline = blk: {
            const shader_module = core.device.createShaderModuleWGSL("font.wgsl", @embedFile("font.wgsl"));
            defer shader_module.release();

            var pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
                .label = "font pipeline layout",
                .bind_group_layouts = &[_]*gpu.BindGroupLayout{
                    projection_matrix_bind_group_layout,
                    font_texture_bind_group_layout,
                },
            }));
            defer pipeline_layout.release();

            const color_target = gpu.ColorTargetState{
                .format = core.descriptor.format,
                .blend = &gpu.BlendState{
                    .alpha = .{
                        .src_factor = .one,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                    .color = .{
                        .src_factor = .src_alpha,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                },
                .write_mask = gpu.ColorWriteMaskFlags.all,
            };
            const fragment = gpu.FragmentState.init(.{
                .module = shader_module,
                .entry_point = "frag_main",
                .targets = &.{color_target},
            });
            const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
                .fragment = &fragment,
                .vertex = gpu.VertexState{
                    .module = shader_module,
                    .entry_point = "vertex_main",
                    .buffers = @ptrCast(&gpu.VertexBufferLayout.init(.{
                        .array_stride = @sizeOf(FontVertex),
                        .attributes = &.{
                            gpu.VertexAttribute{
                                .format = .float32x2,
                                .offset = @offsetOf(FontVertex, "pos"),
                                .shader_location = 0,
                            },
                            gpu.VertexAttribute{
                                .format = .float32x2,
                                .offset = @offsetOf(FontVertex, "tex_coord"),
                                .shader_location = 1,
                            },
                            gpu.VertexAttribute{
                                .format = .float32x4,
                                .offset = @offsetOf(FontVertex, "col"),
                                .shader_location = 2,
                            },
                        },
                    })),
                    .buffer_count = 1,
                },
                .layout = pipeline_layout,
            };
            break :blk core.device.createRenderPipeline(&pipeline_descriptor);
        },
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    app.font_pipeline.release();
    app.font_texture_bind_group.release();
    app.vertex_buffer.release();
}

pub fn update(app: *App) !bool {
    var event_iter = core.pollEvents();
    while (event_iter.next()) |event| {
        switch (event) {
            .close => return true,
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
    pass.setPipeline(app.font_pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(FontVertex) * 6);
    pass.setBindGroup(0, app.projection_matrix_bind_group, null);
    pass.setBindGroup(1, app.font_texture_bind_group, null);
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
