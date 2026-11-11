shader_type spatial;
// Vertical board cladding in world space (barns, sheds): ~20 cm boards with dark gaps, per-board
// tint, grain running up the board, knots, and blotchy grey weathering.
// Faces looking along x use world z across the boards, all others world x; up-facing faces get
// planks running along x.

uniform vec4 base_color : source_color = vec4(0.42, 0.29, 0.19, 1.0);
uniform float board_width = 0.21;
uniform float weather = 0.35;
global uniform float road_wetness;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	// (across, along) the boards.
	vec2 bp = n.y > 0.7 ? world_pos.zx : (n.x > n.z ? vec2(world_pos.z, world_pos.y) : vec2(world_pos.x, world_pos.y));
	float u = bp.x / board_width;
	float id = floor(u);
	float f = fract(u);
	float gap = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.95, 1.0, f));
	// Boards are cut to different lengths: a butt joint every few metres, offset per board.
	float seg = floor(bp.y / 3.1 + hash(vec2(id, 3.0)));
	float joint = 1.0 - smoothstep(0.0, 0.012, abs(fract(bp.y / 3.1 + hash(vec2(id, 3.0))) - 0.5) - 0.497);
	float tone = 0.78 + 0.36 * hash(vec2(id, seg));
	float grain = 0.86 + 0.14 * vnoise(vec2(f * 6.0 + id * 3.1, bp.y * 1.4)) + 0.08 * sin((f * 9.0 + vnoise(vec2(id, bp.y * 0.6)) * 4.0) * 3.14);
	// A few knots.
	vec2 kc = vec2(f - 0.5, fract(bp.y / 0.9 + hash(vec2(id, 7.0))) - 0.5) * vec2(board_width, 0.9);
	float knot = (1.0 - smoothstep(0.008, 0.02, length(kc))) * step(0.8, hash(vec2(id, floor(bp.y / 0.9 + hash(vec2(id, 7.0))))));
	vec3 col = base_color.rgb * tone * grain;
	col = mix(col, col * 0.45, knot);
	// Weathering: blotchy silver-grey.
	float blotch = vnoise(world_pos.xz * 0.8 + world_pos.y * 0.3);
	float grey = clamp(weather * (0.4 + 0.8 * blotch), 0.0, 0.8);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.5, 0.2))) * 1.15, grey);
	col *= mix(0.25, 1.0, gap) * mix(0.8, 1.0, 1.0 - joint);
	col *= mix(1.0, 0.65, clamp(road_wetness, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.92;
	// Board edges catch the light: tilt the normal across each board a little.
	NORMAL_MAP = vec3(0.5 + 0.2 * (smoothstep(0.8, 1.0, f) - smoothstep(0.2, 0.0, f)), 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.6;
}
