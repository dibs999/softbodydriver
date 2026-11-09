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

// Distance to the nearest Voronoi cell border.
float cell_edge(vec2 x) {
	vec2 n = floor(x), f = fract(x), mg = vec2(0.0), mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++)
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash(n + g), hash(n + g + 31.7));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	md = 8.0;
	for (int j = -2; j <= 2; j++)
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = vec2(hash(n + g), hash(n + g + 31.7));
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
		}
	return md;
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
		// Ageing: a crack network in worn stretches, glossy black bitumen sealing over some of the
		// cracks, longitudinal cracks and grit along the edges, oil drips in the lane centres.
		vec2 wp = world_pos.xz;
		float aged = smoothstep(0.52, 0.72, fbm(wp * 0.018 + vec2(41.0, 7.0))) * wear;
		float ce = cell_edge(wp / 1.6) * 1.6;
		float cw = max(fwidth(ce), 0.001);
		float crack = (1.0 - smoothstep(0.004, 0.004 + cw, ce)) * aged * step(0.25, vnoise(wp * 0.7));
		float seal_zone = smoothstep(0.68, 0.78, vnoise(wp * 0.04 + 13.0)) * wear;
		float seal_line = cell_edge(wp / 4.5 + 7.0) * 4.5 + 0.05 * (vnoise(wp * 3.0) - 0.5);
		float seal = (1.0 - smoothstep(0.014, 0.014 + cw * 1.5, seal_line)) * seal_zone * step(0.55, vnoise(wp * 0.45 + 5.0));
		float edge_u = min(u, 1.0 - u) * road_width;      // metres from the outer edge
		float edge_crack = (1.0 - smoothstep(0.006, 0.006 + max(fwidth(edge_u), 0.001), abs(edge_u - 0.55 - 0.12 * (fbm(vec2(UV.y * 0.7, 3.0)) - 0.5)))) * wear * step(0.4, vnoise(wp * 0.3));
		float grit = (1.0 - smoothstep(0.05, 0.45 + 0.3 * fbm(wp * 0.5), edge_u)) * wear;
		float lane_centre = 1.0 - smoothstep(0.0, 0.32 / lane_w, abs(lane_pos - 0.5));
		vec2 oc = floor(wp / 0.9);
		float oil = (1.0 - smoothstep(0.08, 0.30, length(fract(wp / 0.9) - vec2(hash(oc), hash(oc + 2.0))))) * step(0.82, hash(oc + 9.0)) * lane_centre * wear;
		base = mix(base, base * 0.45, max(crack, edge_crack) * 0.85);
		base = mix(base, vec3(0.018), seal * 0.9);
		rough = mix(rough, 0.6, seal);
		base = mix(base, base * vec3(1.25, 1.18, 1.05) + vec3(0.03, 0.025, 0.015), grit * 0.6);
		base = mix(base, base * 0.7, oil * 0.6);
		rough = mix(rough, 0.55, oil * 0.5);
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
