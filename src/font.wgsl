struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
  @location(1) tex_coord: vec2<f32>,
}

@group(0) @binding(0) var<uniform> projection_matrix: mat4x4<f32>;

@vertex fn vertex_main(
  @location(0) pos: vec2<f32>,
  @location(1) tex_coord: vec2<f32>,
  @location(2) col: vec4<f32>,
) -> VertexOutput {
  var vertexOutput: VertexOutput;

  vertexOutput.position = projection_matrix * vec4<f32>(pos, 0, 1);
  vertexOutput.color = col;
  vertexOutput.tex_coord = tex_coord;

  return vertexOutput;
}

@group(1) @binding(0) var t: texture_2d<f32>;
@group(1) @binding(1) var s: sampler;

fn median(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

@fragment fn frag_main(input: VertexOutput) -> @location(0) vec4<f32> {
  var sample = textureSample(t, s, input.tex_coord).rgb;
  var sz = textureDimensions(t).xy;
  var dx = dpdx(input.tex_coord.x) * f32(sz.x);
  var dy = dpdy(input.tex_coord.y) * f32(sz.y);
  var toPixels = 8.0 * inverseSqrt(dx * dx + dy * dy);
  var sigDist = median(sample.r, sample.g, sample.b);
  var w = fwidth(sigDist);
  var opacity = smoothstep(0.5 - w, 0.5 + w, sigDist);

  return vec4(input.color.rgb, opacity);
}
