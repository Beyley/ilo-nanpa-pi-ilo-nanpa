const std = @import("std");

atlas: struct {
    type: []const u8,
    distanceRange: usize,
    size: usize,
    width: usize,
    height: usize,
    yOrigin: []const u8,
},
metrics: struct {
    emSize: usize,
    lineHeight: usize,
    ascender: f32,
    descender: f32,
    underlineY: f32,
    underlineThickness: f32,
},
glyphs: []const struct {
    unicode: u21,
    advance: f32,
    planeBounds: ?Bounds = null,
    atlasBounds: ?Bounds = null,
},
kerning: []const struct {},

pub const Bounds = struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,
};

const Self = @This();

pub fn readAtlas(allocator: std.mem.Allocator) !std.json.Parsed(Self) {
    return try std.json.parseFromSlice(Self, allocator, @embedFile("atlas.json"), .{});
}
