shader_type spatial;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 texture_repeats = vec2(4.5, 6.0);
uniform float road_width = 9.0;
uniform int lanes = 2;
uniform bool dirt = false;
uniform vec4 dirt_tint : source_color = vec4(0.83, 0.68, 0.49, 1.0);
uniform vec4 divider_color : source_color = vec4(0.86, 0.85, 0.77, 1.0);
uniform float wear = 1.0;          // 0 = fresh surface, 1 = typical public road
global uniform float road_wetness;  // set by the weather (darker, glossier)

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.07 + vec2(11.3, 7.9); a *= 0.5; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 surface_uv = UV * texture_repeats;
	vec3 base = texture(surface_color, surface_uv).rgb;
	NORMAL_MAP = texture(surface_normal, surface_uv).rgb;
	NORMAL_MAP_DEPTH = dirt ? 0.54 : 0.38;
	float rough = dirt ? 0.98 : 0.86;
	// Large-scale tone variation (different batches, sun bleaching) in world space.
	float macro = fbm(world_pos.xz * 0.035);
	float fine = fbm(world_pos.xz * 0.6);
	if (dirt) {
		float rut_distance = min(abs(UV.x - 0.31), abs(UV.x - 0.69));
		float shoulder = smoothstep(0.34, 0.50, abs(UV.x - 0.5));
		base *= dirt_tint.rgb;
		base *= mix(0.73, 1.0, smoothstep(0.018, 0.082, rut_distance)) * mix(1.0, 0.84, shoulder);
		base *= mix(0.86, 1.12, macro);
	} else {
		float u = UV.x;
		base *= mix(0.84, 1.10, macro) * mix(0.95, 1.04, fine);
		// Polished wheel tracks: each lane carries two darker, smoother bands.
		float lane_pos = fract(u * float(lanes));
		float lane_w = road_width / float(lanes);
		float track_off = 0.78 / lane_w;   // tyres ~0.78 m either side of the lane centre
		float d1 = abs(lane_pos - (0.5 - track_off)), d2 = abs(lane_pos - (0.5 + track_off));
		float tracks = (1.0 - smoothstep(0.12 / lane_w, 0.36 / lane_w, min(d1, d2))) * wear;
		tracks *= mix(0.6, 1.0, vnoise(vec2(world_pos.x + world_pos.z, 0.0) * 0.08));
		base *= mix(1.0, 0.88, tracks);
		rough = mix(rough, 0.7, tracks);
		// Repair patches: irregular darker rectangles of fresher asphalt.
		vec2 cell = floor(vec2(UV.x * float(lanes) * 1.0, UV.y * 0.18));
		float pick = hash(cell + 3.7);
		vec2 local = fract(vec2(UV.x * float(lanes), UV.y * 0.18));
		float patch_mask = step(0.86, pick) * step(0.12, local.x) * step(local.x, 0.88) * step(0.2, local.y) * step(local.y, 0.2 + 0.5 * hash(cell));
		base = mix(base, base * 0.62 + vec3(0.01), patch_mask * wear);
		rough = mix(rough, 0.92, patch_mask * wear);
		// Markings, slightly worn and dirtier at the wheel tracks.
		float pixel = max(fwidth(u) * 0.55, 0.0002);
		float edge_distance = abs(min(u, 1.0 - u) - 0.22 / road_width);
		float edge = 1.0 - smoothstep(0.06 / road_width - pixel, 0.06 / road_width + pixel, edge_distance);
		float lane_distance = abs(fract(u * float(lanes) + 0.5) - 0.5) / float(lanes);
		float divider = 1.0 - smoothstep(0.06 / road_width - pixel, 0.06 / road_width + pixel, lane_distance);
		float dash_distance = abs(fract(UV.y) - 0.5);
		float dash_pixel = max(fwidth(UV.y) * 0.6, 0.0002);
		divider *= (1.0 - smoothstep(0.24 - dash_pixel, 0.24 + dash_pixel, dash_distance)) * step(0.10, u) * step(u, 0.90);
		float paint_wear = mix(1.0, smoothstep(0.25, 0.65, fine), 0.35 * wear);
		base = mix(base, divider_color.rgb, divider * 0.92 * paint_wear);
		base = mix(base, vec3(0.84, 0.83, 0.78), edge * 0.92 * paint_wear);
		rough = mix(rough, 0.7, max(divider, edge) * paint_wear);
	}
	// Wet roads: darker, mirror-like where water collects (puddles in the wheel tracks first).
	float wetness = clamp(road_wetness * (dirt ? 0.7 : 1.0), 0.0, 1.0);
	base *= mix(1.0, 0.62, wetness);
	rough = mix(rough, 0.12 + 0.25 * fine, wetness);
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.65, wetness);
}
