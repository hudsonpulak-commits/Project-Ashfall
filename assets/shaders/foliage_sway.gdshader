shader_type canvas_item;
// 0.3.19 cheap wind: the crown moves, the trunk stays put. Vertex-only so
// sprite modulate and the day/night CanvasModulate still apply.
// Pixel-quantised so the art stays crisp.

uniform float sway_speed = 1.35;
uniform float sway_px = 1.15;

void vertex() {
	float crown = 1.0 - UV.y;
	crown *= crown;
	// Phase from the sprite origin so neighbours do not sway in lockstep.
	// One shared material: no per-sprite instance uniform (GLES3 leaks those).
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	float phase = fract(sin(dot(floor(origin), vec2(127.1, 311.7))) * 43758.5453) * 6.2831853;
	float wave = sin(TIME * sway_speed + phase);
	VERTEX.x += round(wave * sway_px * crown);
}
