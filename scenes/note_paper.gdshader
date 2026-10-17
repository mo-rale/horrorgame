shader_type canvas_item;
// Aged paper for the story notes (scripts/story_note.gd): fine grain, a few soft
// stains and darker, worn edges. Drawn on a ColorRect that covers the note card.

uniform vec4 paper : source_color = vec4(0.85, 0.8, 0.67, 1.0);
// The card's size in pixels, so the grain stays the same size on any card.
uniform vec2 size = vec2(1200.0, 900.0);
// Different for every note, so no two sheets are stained alike.
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 px = UV * size;
	float scale = size.y / 900.0;
	float grain = noise(px / (1.6 * scale)) * 0.6 + noise(px / (4.0 * scale)) * 0.4;
	float stains = noise(px / (190.0 * scale)) * 0.65 + noise(px / (70.0 * scale)) * 0.35;
	vec2 from_edge = min(UV, 1.0 - UV) * size;
	float edge = min(from_edge.x, from_edge.y) / scale;
	float worn = smoothstep(0.0, 110.0, edge + (noise(px / (24.0 * scale)) - 0.5) * 30.0);
	vec3 color = paper.rgb;
	color *= 0.94 + 0.08 * grain;
	color *= 1.0 - 0.07 * smoothstep(0.45, 0.85, stains);
	color *= mix(0.78, 1.0, worn);
	COLOR = vec4(color, 1.0);
}
