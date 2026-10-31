shader_type canvas_item;
// 0.3.19 ground colour variation (world-space hash, two scales) plus a
// per-chunk wear mask: grass beside roads and doors darkens toward a dirt tone.
// wear_tex is one texel per tile, red = wear 0..1. chunk_origin is the layer's
// world position in pixels.

uniform sampler2D wear_tex : filter_linear, repeat_disable;
uniform vec2 chunk_origin = vec2(0.0);
uniform float chunk_px = 384.0;
uniform float tile_px = 16.0;

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec4 c = COLOR; // batch_08: COLOR already holds the texel in canvas_item; *COLOR squared every base tile
	// 0.4.3 smooth world-space value noise (two octaves, ~3 and ~9 tiles) instead of a
	// per-tile hash: same +-0.08 range, no tile-sized brightness boxes
	vec2 q = world_px / tile_px;
	float k = ((vnoise(q / 3.0) * 0.7 + vnoise(q / 9.0 + vec2(19.0, 7.0)) * 0.3) - 0.5) * 0.16;
	// 0.4.4 the per-tile mask was read nearest -> tile-sized dark squares in towns.
	// Read it filtered, through a domain warp (~0.6 tile), on a texture with a
	// one-tile apron (CHUNK+2 texels): organic, seamless wear edges.
	vec2 tl = (world_px - chunk_origin) / tile_px;
	vec2 wq = q * 0.6;
	tl += (vec2(vnoise(wq), vnoise(wq + vec2(41.0, 13.0))) - 0.5) * 1.2;
	tl += (vec2(vnoise(q * 2.1 + 5.0), vnoise(q * 2.1 + vec2(77.0, 3.0))) - 0.5) * 0.35;
	float n_t = chunk_px / tile_px + 2.0;
	vec4 mask = texture(wear_tex, clamp((tl + 1.0) / n_t, vec2(0.5 / n_t), vec2(1.0 - 0.5 / n_t)));
	// Green marks grass and dirt. Ash, stone and water stay as painted so night
	// ground (the Scorch) does not get an extra darken.
	c.rgb *= mix(vec3(1.0), vec3(1.0 + k * 1.05, 1.0 + k * 0.55, 1.0 + k * 0.15), mask.g);
	float wear = mask.r;
	vec3 dirt = vec3(0.55, 0.42, 0.26);
	c.rgb = mix(c.rgb, c.rgb * dirt + vec3(0.06, 0.04, 0.02), clamp(wear, 0.0, 1.0) * 0.55);
	COLOR = c;
}
