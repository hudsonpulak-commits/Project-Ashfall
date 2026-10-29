shader_type canvas_item;
// 0.3.19 ground colour variation (world-space hash, two scales) plus a
// per-chunk wear mask: grass beside roads and doors darkens toward a dirt tone.
// wear_tex is one texel per tile, red = wear 0..1. chunk_origin is the layer's
// world position in pixels.

uniform sampler2D wear_tex : filter_nearest, repeat_disable;
uniform vec2 chunk_origin = vec2(0.0);
uniform float chunk_px = 384.0;
uniform float tile_px = 16.0;

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 tile = floor(world_px / tile_px);
	float n = fract(sin(dot(tile, vec2(127.1, 311.7))) * 43758.5453);
	float n2 = fract(sin(dot(floor(tile / 3.0) + vec2(19.0, 7.0), vec2(269.5, 183.3))) * 43758.5453);
	float k = (n * 0.7 + n2 * 0.3 - 0.5) * 0.16;
	vec2 local = (world_px - chunk_origin) / max(chunk_px, 1.0);
	vec4 mask = texture(wear_tex, clamp(local, vec2(0.001), vec2(0.999)));
	// Green marks grass and dirt. Ash, stone and water stay as painted so night
	// ground (the Scorch) does not get an extra darken.
	c.rgb *= mix(vec3(1.0), vec3(1.0 + k * 1.05, 1.0 + k * 0.55, 1.0 + k * 0.15), mask.g);
	float wear = mask.r;
	vec3 dirt = vec3(0.55, 0.42, 0.26);
	c.rgb = mix(c.rgb, c.rgb * dirt + vec3(0.06, 0.04, 0.02), clamp(wear, 0.0, 1.0) * 0.55);
	COLOR = c;
}
