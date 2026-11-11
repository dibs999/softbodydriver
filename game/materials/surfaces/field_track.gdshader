shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;
// Dirt track: two worn ruts with a grassy crown, ragged grassy edges, dry dust and damp patches,
// and puddles that collect in the ruts (more of them when the weather is wet).

uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float width = 6.4;
uniform float greenery = 0.7;
global uniform float road_wetness;

varying vec3 world_pos;

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
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(7.1, 3.3); a *= 0.5; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tile = UV * vec2(width / 1.8, 5.0);
	vec2 wp = world_pos.xz;
	float macro = fbm(wp * 0.035);
	// Track-aligned sample plus a sharper world-space one: gravel stays crisp up close.
	vec3 grit = texture(soil, wp / 1.3).rgb;
	vec3 earth = mix(texture(soil, tile).rgb, grit, 0.55) * vec3(0.58, 0.44, 0.30);
	earth = mix(vec3(dot(earth, vec3(0.33))), earth, 1.15) * (0.6 + 0.8 * grit.r);
	// Loose pebbles: one at a random spot in most 12 cm cells, light or dark.
	vec2 pc = wp / 0.12;
	vec2 cell_id = floor(pc);
	vec2 jitter = vec2(hash(cell_id), hash(cell_id + 17.0));
	float pd = length(fract(pc) - jitter);
	float pr = 0.08 + 0.17 * hash(cell_id + 5.0);
	float pebble = (1.0 - smoothstep(pr - 0.06, pr, pd)) * step(0.35, hash(cell_id + 9.0));
	earth = mix(earth, earth * (hash(cell_id + 3.0) > 0.5 ? 1.3 : 0.5), pebble * 0.7);
	// Sparse larger stones (fist size) with a lit and a shadowed side, so they read as raised.
	vec2 sc = wp / 0.45;
	vec2 sid = floor(sc);
	vec2 sv = fract(sc) - vec2(hash(sid + 2.0), hash(sid + 6.0)) * 0.5 - 0.25;
	float sr = 0.10 + 0.08 * hash(sid + 1.0);
	float stone = (1.0 - smoothstep(sr * 0.75, sr, length(sv * vec2(1.0, 1.3)))) * step(0.82, hash(sid + 13.0));
	float lit = clamp(0.75 - dot(normalize(sv + 1e-4), vec2(0.6, 0.8)) * 0.6 * length(sv) / sr, 0.35, 1.35);
	vec3 rock = earth * vec3(0.82, 0.84, 0.90) * (0.72 + 0.3 * hash(sid + 4.0)) * mix(1.0, lit, 0.45);
	float stone_shadow = (1.0 - smoothstep(sr, sr * 1.5, length(sv - vec2(0.03, 0.04)))) * step(0.82, hash(sid + 13.0)) * (1.0 - stone);
	// Dry, pale dust and dark damp earth in patches along the track.
	earth = mix(earth * vec3(1.18, 1.12, 1.02), earth * vec3(0.62, 0.58, 0.55), smoothstep(0.4, 0.75, macro));
	earth *= 0.88 + 0.24 * vnoise(wp * 0.9);
	vec3 plants = texture(grass, tile * 0.72).rgb * vec3(0.73, 0.85, 0.57);
	// Ruts meander a little and vary in width.
	float meander = 0.18 * (fbm(vec2(UV.y * 0.9, 1.7)) - 0.5) * 2.0;
	float across = (UV.x - 0.5) * width - meander;
	float rut_w = 0.79 + 0.08 * (vnoise(vec2(UV.y * 2.3, 4.1)) - 0.5);
	float rut = min(abs(across - rut_w), abs(across + rut_w));
	float worn = 1.0 - smoothstep(0.25, 0.60 + 0.12 * vnoise(wp * 0.7), rut);
	float center = (1.0 - smoothstep(0.2, 0.58, abs(across))) * greenery * (0.7 + 0.5 * vnoise(wp * 0.6));
	// Ragged edges: grass creeps in by up to a metre.
	float edge_noise = (fbm(wp * 0.35) - 0.5) * 1.6;
	float shoulder = smoothstep(width * 0.30 + edge_noise * 0.4, width * 0.5 + edge_noise * 0.3, abs(across));
	// Compacted ruts: darker, with fine tyre grooves running along them; lighter lips of pushed-up
	// soil on both sides of each rut.
	float grooves = 0.95 + 0.05 * sin(across * 70.0 + vnoise(vec2(UV.y * 8.0, across * 4.0)) * 6.0) * (0.4 + 0.6 * vnoise(wp * 2.0));
	float lip = smoothstep(0.30, 0.42, rut) * (1.0 - smoothstep(0.42, 0.62, rut));
	vec3 track_earth = earth * mix(1.0, 0.74 * grooves, worn) * (1.0 + 0.16 * lip);
	track_earth = mix(track_earth, track_earth * 0.6, stone_shadow * 0.6 * (1.0 - worn));
	track_earth = mix(track_earth, rock, stone * (1.0 - worn * 0.8));
	vec3 col = mix(track_earth, plants, clamp(max(center, shoulder * 0.9), 0.0, 1.0));
	// Puddles in the ruts.
	float wet = clamp(road_wetness, 0.0, 1.0);
	float pool_n = fbm(wp * 0.22 + vec2(3.0, 9.0)) * 0.75 + vnoise(wp * 1.4) * 0.25;
	float pool = smoothstep(0.66 - 0.14 * wet, 0.72 - 0.14 * wet, pool_n) * smoothstep(0.3, 0.8, worn);
	col = mix(col, vec3(0.10, 0.09, 0.08), pool * 0.85);
	col *= mix(1.0, 0.7, wet);
	ALBEDO = col;
	NORMAL_MAP = mix(texture(soil_normal, tile).rgb, vec3(0.5, 0.5, 1.0), pool);
	NORMAL_MAP_DEPTH = 0.45;
	ROUGHNESS = mix(mix(0.98, 0.6, wet * worn), 0.06, pool);
	SPECULAR = mix(0.5, 0.65, pool);
	ALPHA = 1.0 - smoothstep(0.40 + edge_noise * 0.02, 0.5, abs(UV.x - 0.5));
}
