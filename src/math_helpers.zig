const std = @import("std");
const math = @import("mach").math;

pub fn orthographicOffCenter(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) math.Mat4x4 {
    std.debug.assert(!std.math.approxEqAbs(f32, far, near, 0.001));

    const r = 1 / (far - near);

    return math.mat4x4(
        &math.vec4(2 / (right - left), 0.0, 0.0, 0.0),
        &math.vec4(0.0, 2 / (top - bottom), 0.0, 0.0),
        &math.vec4(0.0, 0.0, r, 0.0),
        &math.vec4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), -r * near, 1.0),
    );
}
