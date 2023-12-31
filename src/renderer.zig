const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const math = @import("mach").math;
const math_helpers = @import("math_helpers.zig");
const zigimg = @import("zigimg");
const Atlas = @import("atlas.zig");

const Gfx = @import("gfx.zig");

const Self = @This();

const RenderBuffer = struct {
    vtx_buf: *gpu.Buffer,
    idx_buf: *gpu.Buffer,
    used_vtx: u64 = 0,
    used_idx: u64 = 0,
    // scissor: Gfx.RectU,
    ///Recording periods that this buffer has been stuck in the queue without being re-used
    recording_periods_since_used: usize = 0,
};

gfx: *Gfx,
arena_allocator: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,
///The main texture of the renderer, aka the atlas
started: bool,
recorded_buffers: std.ArrayList(RenderBuffer),
queued_buffers: std.ArrayList(RenderBuffer),
recording_buffer: ?RenderBuffer = null,
//The in-progress CPU side buffers that get uploaded to the GPU upon a call to dump()
cpu_vtx_raw: []u8,
cpu_vtx_positions: []math.Vec2,
cpu_vtx_tex_coords: []math.Vec2,
cpu_vtx_colors: []math.Vec4,
cpu_idx: []IndexType,
// current_scissor: @Vector(4, usize),

pub fn init(allocator: std.mem.Allocator, gfx: *Gfx) !Self {
    var self: Self = Self{
        .gfx = gfx,
        .started = false,
        .arena_allocator = std.heap.ArenaAllocator.init(allocator),
        .recorded_buffers = undefined,
        .allocator = undefined,
        .queued_buffers = undefined,
        .cpu_vtx_raw = undefined,
        .cpu_vtx_positions = undefined,
        .cpu_vtx_tex_coords = undefined,
        .cpu_vtx_colors = undefined,
        .cpu_idx = undefined,
        // .current_scissor = gfx.viewport,
    };
    self.allocator = self.arena_allocator.allocator();
    self.recorded_buffers = std.ArrayList(RenderBuffer).init(self.allocator);
    self.queued_buffers = std.ArrayList(RenderBuffer).init(self.allocator);
    self.cpu_vtx_raw = try self.allocator.alloc(u8, vtx_buf_size);
    self.cpu_vtx_positions = @as([*]math.Vec2, @alignCast(@ptrCast(self.cpu_vtx_raw.ptr)))[0..vtx_per_buf];
    self.cpu_vtx_tex_coords = @as([*]math.Vec2, @alignCast(@ptrCast(self.cpu_vtx_raw.ptr)))[vtx_per_buf .. vtx_per_buf * 2];
    self.cpu_vtx_colors = @as([*]math.Vec4, @alignCast(@ptrCast(self.cpu_vtx_raw[@sizeOf(math.Vec2) * 2 * vtx_per_buf ..])))[0..vtx_per_buf];
    self.cpu_idx = try self.allocator.alloc(IndexType, idx_per_buf);

    //I think quad_per_buf * 3 is a good amount of tris for most 2d scenes
    const common_max_capacity = 3;

    try self.recorded_buffers.ensureTotalCapacity(common_max_capacity);
    try self.queued_buffers.ensureTotalCapacity(common_max_capacity);

    try self.createRenderBuffer();

    return self;
}

const quad_per_buf = 5000;
const vtx_per_buf = quad_per_buf * 4;
const vtx_buf_size = (@sizeOf(math.Vec2) + @sizeOf(math.Vec2) + @sizeOf(math.Vec4)) * vtx_per_buf;
const idx_per_buf = quad_per_buf * 6;
const IndexType = u16;

fn createRenderBuffer(self: *Self) !void {
    try self.queued_buffers.append(RenderBuffer{
        .vtx_buf = core.device.createBuffer(&gpu.Buffer.Descriptor{
            .label = "render buffer vtx buf",
            .size = @sizeOf(u8) * vtx_buf_size,
            .usage = .{ .vertex = true, .copy_dst = true },
        }),
        .idx_buf = core.device.createBuffer(&gpu.Buffer.Descriptor{
            .label = "render buffer idx buf",
            .size = @sizeOf(IndexType) * idx_per_buf,
            .usage = .{ .index = true, .copy_dst = true },
        }),
        // .scissor = self.gfx.viewport,
    });
}

///Begins recording draw commands
pub fn begin(self: *Self) !void {
    //Ensure we arent started yet
    std.debug.assert(!self.started);
    //Ensure we dont have a current recording buffer
    std.debug.assert(self.recording_buffer == null);

    //Go through all recorded buffers, and set their used counts to 0, resetting them for the next use
    for (0..self.recorded_buffers.items.len) |i| {
        self.recorded_buffers.items[i].used_vtx = 0;
        self.recorded_buffers.items[i].used_idx = 0;
    }

    //Move all recorded buffers into the queued buffers list
    try self.queued_buffers.appendSlice(self.recorded_buffers.items);
    //Clear out the recorded buffer list
    self.recorded_buffers.clearRetainingCapacity();

    //Pop the last item out of the queued buffers, and put it onto the recording buffer
    self.recording_buffer = self.queued_buffers.pop();

    //Mark that we have started recording
    self.started = true;

    //Reset the cached scissor to the current viewport
    // self.current_scissor = self.gfx.viewport;
}

///Ends the recording period, prepares for calling draw()
pub fn end(self: *Self) !void {
    std.debug.assert(self.started);

    try self.dump();

    //TODO: iterate all the unused queued buffers, increment their "time since used" counts,
    //      and dispose ones that have been left for some amount of times

    //Mark that we have finished recording
    self.started = false;
}

// pub fn setScissor(self: *Self, rect: Gfx.RectU) !void {
//     //If the scissor is the same, then dont do anything
//     const eql = rect == self.current_scissor;
//     if (eql[0] and eql[1] and eql[2] and eql[3]) {
//         return;
//     }

//     //Dump the current things to a buffer, since we need to start a new draw call each time the scissor rectangle changes
//     try self.dump();

//     //If theres no more queued buffers,
//     if (self.queued_buffers.items.len == 0) {
//         //Create a new render buffer
//         try self.createRenderBuffer();
//     }

//     //Pop the latest buffer off the queue
//     self.recording_buffer = self.queued_buffers.pop();

//     //Update the current scissor
//     self.current_scissor = rect;

//     //Set the current recording buffers scissor to the new one
//     self.recording_buffer.?.scissor = rect;
// }

// pub fn resetScissor(self: *Self) !void {
//     try self.setScissor(self.gfx.viewport);
// }

///Dumps the current recording buffer to the recorded list, or to the unused list, if empty
///Guarentees that self.recording_buffer == null after the call, caller must reset it in whatever way needed.
fn dump(self: *Self) !void {
    std.debug.assert(self.started);
    std.debug.assert(self.recording_buffer != null);

    if (self.recording_buffer) |recording_buffer| {
        //If it was used,
        if (recording_buffer.used_idx != 0) {
            //Write the CPU buffers to the GPU buffer
            core.queue.writeBuffer(recording_buffer.vtx_buf, 0, self.cpu_vtx_raw);
            core.queue.writeBuffer(recording_buffer.idx_buf, 0, self.cpu_idx[0..recording_buffer.used_idx]);

            //Add to the recorded buffers
            try self.recorded_buffers.append(recording_buffer);
        } else {
            //Add to the empty queued buffers
            try self.queued_buffers.append(recording_buffer);
        }
    }

    //Mark that there is no recording buffer anymore
    self.recording_buffer = null;
}

pub const ReservedData = struct {
    vtx_pos: []math.Vec2,
    vtx_tex: []math.Vec2,
    vtx_col: []math.Vec4,
    idx: []IndexType,
    idx_offset: u16,

    pub fn copyIn(self: ReservedData, pos: []const math.Vec2, tex: []const math.Vec2, col: []const math.Vec4, idx: []const IndexType) void {
        @memcpy(self.vtx_pos, pos);
        @memcpy(self.vtx_tex, tex);
        @memcpy(self.vtx_col, col);
        @memcpy(self.idx, idx);
    }
};

pub inline fn reserveTexQuad(
    self: *Self,
    codepoint: u21,
    position: math.Vec2,
    scale: math.Vec2,
    col: math.Vec4,
) !void {
    const uvs = self.gfx.getTexUVsFromAtlas(codepoint);
    const size = self.gfx.getTexSizeFromAtlas(codepoint);

    var reserved = try self.reserve(4, 6);
    reserved.copyIn(&.{
        position,
        position.add(&math.vec2(size.x(), 0).mul(&scale)),
        position.add(&math.vec2(0, size.y()).mul(&scale)),
        position.add(&size.mul(&scale)),
    }, &.{
        math.vec2(uvs.left, uvs.top),
        math.vec2(uvs.right, uvs.top),
        math.vec2(uvs.left, uvs.bottom),
        math.vec2(uvs.right, uvs.bottom),
    }, &.{
        col, col, col, col,
    }, &.{
        0 + reserved.idx_offset,
        2 + reserved.idx_offset,
        1 + reserved.idx_offset,
        1 + reserved.idx_offset,
        2 + reserved.idx_offset,
        3 + reserved.idx_offset,
    });
}

pub fn reserve(self: *Self, vtx_count: u64, idx_count: u64) !ReservedData {
    //Assert that we arent trying to reserve more than the max buffer size
    std.debug.assert(vtx_count < vtx_per_buf);
    std.debug.assert(idx_count < idx_per_buf);
    //Assert that we have a buffer to record to
    std.debug.assert(self.recording_buffer != null);
    //Assert that we have started recording
    std.debug.assert(self.started);

    const recording_buf: RenderBuffer = self.recording_buffer.?;

    //If the vertex count or index count would put us over the limit of the current recording buffer
    if (recording_buf.used_vtx + vtx_count > vtx_per_buf or recording_buf.used_idx + idx_count > idx_per_buf) {
        try self.dump();

        //If theres no more queued buffers,
        if (self.queued_buffers.items.len == 0) {
            //Create a new render buffer
            try self.createRenderBuffer();
        }

        //Pop the latest buffer off the queue
        self.recording_buffer = self.queued_buffers.pop();

        // self.recording_buffer.?.scissor = self.current_scissor;
    }

    //Increment the recording buffer's counts
    self.recording_buffer.?.used_vtx += vtx_count;
    self.recording_buffer.?.used_idx += idx_count;

    const old_used_vtx = self.recording_buffer.?.used_vtx - vtx_count;

    //Return the 2 slices of data
    return .{
        .vtx_pos = self.cpu_vtx_positions[old_used_vtx..self.recording_buffer.?.used_vtx],
        .vtx_tex = self.cpu_vtx_tex_coords[old_used_vtx..self.recording_buffer.?.used_vtx],
        .vtx_col = self.cpu_vtx_colors[old_used_vtx..self.recording_buffer.?.used_vtx],
        .idx = self.cpu_idx[self.recording_buffer.?.used_idx - idx_count .. self.recording_buffer.?.used_idx],
        .idx_offset = @intCast(self.recording_buffer.?.used_vtx - vtx_count),
    };
}

pub fn draw(self: *Self, encoder: *gpu.RenderPassEncoder) !void {
    //We should never be started
    std.debug.assert(!self.started);

    //Set the pipeline
    encoder.setPipeline(self.gfx.font_pipeline);
    encoder.setBindGroup(0, self.gfx.projection_matrix_bind_group, null);
    encoder.setBindGroup(1, self.gfx.font_texture_bind_group, null);

    for (self.recorded_buffers.items) |recorded_buffer| {
        // encoder.setScissor(recorded_buffer.scissor);
        encoder.setVertexBuffer(0, recorded_buffer.vtx_buf, 0, @sizeOf(math.Vec2) * vtx_per_buf);
        encoder.setVertexBuffer(1, recorded_buffer.vtx_buf, @sizeOf(math.Vec2) * vtx_per_buf, @sizeOf(math.Vec2) * vtx_per_buf);
        encoder.setVertexBuffer(2, recorded_buffer.vtx_buf, @sizeOf(math.Vec2) * 2 * vtx_per_buf, @sizeOf(math.Vec4) * vtx_per_buf);
        encoder.setIndexBuffer(recorded_buffer.idx_buf, .uint16, 0, idx_per_buf * @sizeOf(IndexType));
        encoder.drawIndexed(@intCast(recorded_buffer.used_idx), 1, 0, 0, 0);
    }
}

pub fn deinit(self: *Self) void {
    //TODO: iterate over all recorded and queued buffers, and dispose the GPU objects

    //De-init all the resources
    self.arena_allocator.deinit();
}
