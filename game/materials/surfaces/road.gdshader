shader_type spatial;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 texture_repeats = vec2(4.5, 6.0);
uniform float road_width = 9.0;
uniform int lanes = 2;
uniform bool dirt = false;
uniform vec4 dirt_tint : source_color = vec4(0.83, 0.68, 0.49, 1.0);
// Dirt roads: colour of the terrain beside the road (alpha 0 = off). The outer metre or two blends
// into it, so a graded track does not end on a darker band.
uniform vec4 ground_color : source_color = vec4(0.0);
uniform vec4 divider_color : source_color = vec4(0.86, 0.85, 0.77, 1.0);
uniform float v_metres = 12.0;     // metres per UV.y unit along the road (road_mesh v_scale)
// Centre-line dashes: period and painted share (German rural Leitlinie: 6 m line, 12 m gap).
uniform float dash_period = 12.0;
uniform float dash_fraction = 0.48;
// Motorway layout (0 = lanes across the whole width): a hard shoulder of this width on one side
// (high u when shoulder_high_u), a safety strip on the other, a broad solid line between lane and
// shoulder and lanes of equal width in between.
uniform float shoulder_m = 0.0;
uniform bool shoulder_high_u = true;
uniform float inner_strip_m = 0.0;
uniform float edge_line_m = 0.12;
uniform float wear = 1.0;          // 0 = fresh surface, 1 = typical public road
uniform bool markings = true;      // false: unmarked (village streets)
// The asphalt photo averages an albedo of 0.015, darker than even fresh asphalt (~0.04); weathered
// road surface is ~0.06-0.1; this gain brings it to ~0.065 (the grain stays the photo's).
uniform float asphalt_gain = 4.0;
// Rough road surfaces scatter back towards the light: under headlights, whose source sits beside
// the driver's eye, a road lit at a grazing angle looks many times brighter than a matt (Lambert)
// surface would (road-lighting luminance coefficients, here on the generous side: a screen has no
// dark-adapted eye). Gain of that retro lobe over Lambert.
uniform float retro_gain = 25.0;
global uniform float road_wetness;  // set by the weather (darker, glossier)

varying vec3 world_pos;
varying vec3 geo_normal;   // view space, without the normal map

float hash(vec2 p) {
	p = mod(p, 512.0);   // world coordinates of a few km would leave the fract below without precision
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
	geo_normal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 surface_uv = UV * texture_repeats;
	vec3 base = texture(surface_color, surface_uv).rgb;
	if (!dirt) base *= asphalt_gain;
	NORMAL_MAP = texture(surface_normal, surface_uv).rgb;
	NORMAL_MAP_DEPTH = dirt ? 0.54 : 0.38;
	float rough = dirt ? 0.98 : 0.86;
	// Large-scale tone variation (different batches, sun bleaching) in world space.
	float macro = fbm(world_pos.xz * 0.035);
	float fine = fbm(world_pos.xz * 0.6);
	float puddle = 0.0;
	if (dirt) {
		float rut_distance = min(abs(UV.x - 0.31), abs(UV.x - 0.69));
		float shoulder = smoothstep(0.34, 0.50, abs(UV.x - 0.5));
		base *= dirt_tint.rgb;
		base *= mix(0.73, 1.0, smoothstep(0.018, 0.082, rut_distance)) * mix(1.0, 1.1, shoulder);
		base *= mix(0.86, 1.12, macro);
		float along = UV.y * v_metres;
		float across = (UV.x - 0.5) * road_width;   // metres from the centre line
		// Loose gravel thrown out of the wheel tracks: a windrow in the middle and at the shoulders.
		float windrow = (1.0 - smoothstep(0.2, 0.85, abs(across))) * 0.8
			+ smoothstep(road_width * 0.5 - 1.5, road_width * 0.5 - 0.4, abs(across));
		windrow *= 0.55 + 0.45 * vnoise(vec2(along * 0.15, across * 0.7));
		base = mix(base, base * vec3(1.20, 1.14, 1.05), windrow * 0.7);
		// Scattered stones, more of them in the loose gravel: two sizes, irregular outlines, a lit and
		// a shadowed side. They fade out with distance, where a grid of dots would read as a pattern.
		float cam_d = length(world_pos - CAMERA_POSITION_WORLD);
		float near = 1.0 - smoothstep(9.0, 26.0, cam_d);
		for (int k = 0; k < 2; k++) {
			float density = k == 0 ? 3.1 : 7.3;
			vec2 sp = vec2(across, along) * density + float(k) * 17.3;
			sp.x += hash(vec2(floor(sp.y), float(k) + 4.0)) * 3.7;   // stagger rows: no visible grid
			vec2 sc = floor(sp);
			vec2 sf = fract(sp) - vec2(hash(sc), hash(sc + 5.0)) * 0.7 - 0.15;
			float r = (k == 0 ? 0.13 : 0.18) * (0.6 + 0.6 * hash(sc + 2.0));
			float shape = length(sf * vec2(1.0, 0.75 + 0.5 * hash(sc + 8.0))) + (vnoise(sp * 5.0) - 0.5) * 0.07;
			float present = step((k == 0 ? 0.80 : 0.86) - windrow * 0.3, hash(sc + 11.0));
			float stone = (1.0 - smoothstep(r * 0.7, r, shape)) * present * near;
			float lit = clamp(1.0 - dot(sf, vec2(0.6, 0.8)) / max(r, 1e-3) * 0.5, 0.6, 1.35);
			float shade = (1.0 - smoothstep(r, r * 1.6, length(sf - vec2(0.04, 0.05)))) * present * near * (1.0 - stone);
			vec3 rock = base * vec3(0.96, 0.94, 0.92) * (0.7 + 0.5 * hash(sc + 3.0)) * lit;
			base = mix(base, base * 0.78, shade * 0.6);
			base = mix(base, rock, stone * 0.85);
		}
		// Washboard corrugations in patches, deepest in the wheel tracks; faded with distance, where
		// the ripples alias into bands.
		float wb_zone = smoothstep(0.5, 0.72, vnoise(vec2(along * 0.025, 2.0))) * mix(1.0, 0.4, smoothstep(0.03, 0.1, rut_distance));
		float ripple = sin(along * 8.4 + vnoise(vec2(along * 0.2, across * 0.3)) * 2.0);
		base *= 1.0 - wb_zone * 0.09 * (ripple * 0.5 + 0.5) * (1.0 - smoothstep(14.0, 40.0, cam_d));
		// Blend the outer edge into the terrain beside the road.
		if (ground_color.a > 0.0) {
			float edge_dist = (0.5 - abs(UV.x - 0.5)) * road_width + (fbm(world_pos.xz * 0.45) - 0.5) * 1.4;
			float blend = 1.0 - smoothstep(0.2, 2.0, edge_dist);
			base = mix(base, ground_color.rgb * mix(0.9, 1.08, fine), blend * 0.85);
		}
		// Potholes with a lighter broken rim; they hold water in the rain.
		vec2 pp = vec2(across, along) / 2.5;
		vec2 pc = floor(pp);
		vec2 pf = fract(pp) - 0.5;
		float hole_r = 0.17 + 0.12 * hash(pc + 1.0);
		float hd = length(pf * vec2(1.0, 1.3)) + (vnoise(pp * 9.0) - 0.5) * 0.06;
		float has_hole = step(0.93, hash(pc + 7.0)) * (1.0 - shoulder);
		puddle = (1.0 - smoothstep(hole_r * 0.7, hole_r, hd)) * has_hole;
		float rim = smoothstep(hole_r * 0.8, hole_r, hd) * (1.0 - smoothstep(hole_r, hole_r * 1.3, hd)) * has_hole;
		// Dry, a pothole is a shallow shadowed hollow; it only turns dark once water stands in it.
		base = mix(base, base * mix(0.8, 0.55, smoothstep(0.3, 0.7, road_wetness)), puddle);
		base = mix(base, base * 1.15, rim * 0.5);
	} else {
		float u = UV.x;
		float along_m = UV.y * v_metres;
		float across_m = (u - 0.5) * road_width;
		base *= mix(0.84, 1.10, macro) * mix(0.95, 1.04, fine);
		// Mid-distance mottling (where the aggregate texture has already blurred into its mean):
		// blotches of a few metres, slightly stretched along the road by the paver.
		float mottle = fbm(vec2(along_m * 0.11, across_m * 0.32) + vec2(3.1, 8.7));
		base *= mix(0.91, 1.08, mottle);
		// Aggregate contrast that survives the mipmaps: a second, rotated sample of the texture at
		// another scale, only in the near field where it can still be resolved.
		float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
		vec2 ruv = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * surface_uv * 2.37;
		vec3 grain = texture(surface_color, ruv).rgb;
		float grain_l = dot(grain, vec3(0.333)) / max(dot(base, vec3(0.333)), 0.01);
		base *= mix(1.0, clamp(0.55 + 0.45 * grain_l * 1.6, 0.7, 1.4), (1.0 - smoothstep(4.0, 22.0, cam_dist)) * 0.6);
		// Polished wheel tracks: each lane carries two darker, smoother bands.
		float lane_pos = fract(u * float(lanes));
		float lane_w = road_width / float(lanes);
		float track_off = 0.78 / lane_w;   // tyres ~0.78 m either side of the lane centre
		float d1 = abs(lane_pos - (0.5 - track_off)), d2 = abs(lane_pos - (0.5 + track_off));
		// The tracks wander a little and are fainter or stronger along the road, with soft edges.
		float wander = (vnoise(vec2(along_m * 0.03, 1.0 + floor(u * float(lanes)))) - 0.5) * 0.25 / lane_w;
		d1 = abs(lane_pos - wander - (0.5 - track_off));
		d2 = abs(lane_pos - wander - (0.5 + track_off));
		float tracks = (1.0 - smoothstep(0.08 / lane_w, 0.42 / lane_w, min(d1, d2))) * wear;
		tracks *= mix(0.35, 1.0, vnoise(vec2(along_m * 0.045, 7.0 + floor(u * float(lanes)) * 3.0)));
		tracks *= mix(0.75, 1.0, vnoise(vec2(along_m * 0.9, across_m * 2.5)));
		base *= mix(1.0, 0.91, tracks);
		rough = mix(rough, 0.76, tracks);
		// Longitudinal construction joint between paver lanes (on the lane lines and at the
		// centre of single-lane halves): a thin darker seam with a sealed, glossy strip.
		float joint_d = abs(fract(u * float(lanes) + 0.5) - 0.5) * lane_w + 0.18;   // 18 cm beside the line
		float joint_px = max(fwidth(joint_d), 0.002);
		float joint = (1.0 - smoothstep(0.012, 0.012 + joint_px, abs(joint_d - 0.18 - 0.18)))
			* step(0.10, u) * step(u, 0.90) * wear;
		joint *= 0.55 + 0.45 * vnoise(vec2(along_m * 0.6, 3.0));
		base = mix(base, base * 0.6, joint * 0.7);
		float joint_seal = (1.0 - smoothstep(0.03, 0.09, abs(joint_d - 0.36))) * step(0.10, u) * step(u, 0.90)
			* smoothstep(0.55, 0.7, vnoise(vec2(along_m * 0.02, 9.0))) * wear;
		base = mix(base, base * 0.55, joint_seal * 0.6);
		rough = mix(rough, 0.62, joint_seal * 0.6);
		// Skid marks: now and then a pair of dark rubber streaks in a lane, fading out at both ends.
		float skid_cell = floor(along_m / 60.0);
		float skid_lane = floor(u * float(lanes));
		float has_skid = step(0.80, hash(vec2(skid_cell, skid_lane + 17.0))) * wear;
		float skid_start = hash(vec2(skid_cell, skid_lane + 3.0)) * 30.0;
		float skid_len = 9.0 + hash(vec2(skid_cell, skid_lane + 5.0)) * 22.0;
		float skid_t = (along_m - skid_cell * 60.0 - skid_start) / skid_len;
		float skid_along = smoothstep(0.0, 0.15, skid_t) * (1.0 - smoothstep(0.55, 1.0, skid_t));
		float skid_drift = (hash(vec2(skid_cell, skid_lane + 9.0)) - 0.5) * 0.6 * skid_t / lane_w;
		float s1 = abs(lane_pos - skid_drift - (0.5 - track_off * 1.05));
		float s2 = abs(lane_pos - skid_drift - (0.5 + track_off * 1.05));
		float skid = (1.0 - smoothstep(0.07 / lane_w, 0.11 / lane_w, min(s1, s2))) * skid_along * has_skid;
		skid *= 0.6 + 0.4 * vnoise(vec2(along_m * 3.0, across_m * 8.0));
		base = mix(base, base * 0.42, skid * 0.75);
		rough = mix(rough, 0.68, skid * 0.6);
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
		// Fatigue (alligator) cracking: small irregular cells, warped so no polygon shows, mostly in
		// the wheel tracks and along the edge where the loads are; faded out with distance before
		// the lines alias into a net.
		vec2 warp = vec2(fbm(wp * 1.3 + 3.0), fbm(wp * 1.3 + 17.0)) - 0.5;
		float ce = cell_edge((wp + warp * 0.35) / 0.55) * 0.55;
		float cw = max(fwidth(ce), 0.001);
		float load_zone = max(tracks * 1.3, 1.0 - smoothstep(0.4, 1.1, min(u, 1.0 - u) * road_width));
		float crack = (1.0 - smoothstep(0.0025, 0.0025 + cw, ce)) * aged * clamp(load_zone, 0.0, 1.0)
			* step(0.3, vnoise(wp * 1.1)) * (1.0 - smoothstep(12.0, 35.0, cam_dist));
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
		// Soil and leaf litter washed onto the last few decimetres, in irregular tongues.
		float spill_w = 0.12 + 0.35 * fbm(vec2(along_m * 0.35, 5.0));
		float spill = (1.0 - smoothstep(spill_w * 0.4, spill_w, edge_u)) * wear * (shoulder_m > 0.0 ? 0.6 : 1.0);
		base = mix(base, vec3(0.20, 0.17, 0.12) * mix(0.8, 1.2, fine), spill * 0.55);
		rough = mix(rough, 0.95, spill);
		base = mix(base, base * 0.7, oil * 0.6);
		rough = mix(rough, 0.55, oil * 0.5);
		// Markings, slightly worn and dirtier at the wheel tracks.
		float pixel = max(fwidth(u) * 0.55, 0.0002);
		float edge_distance = abs(min(u, 1.0 - u) - 0.22 / road_width);
		float edge = 1.0 - smoothstep(0.06 / road_width - pixel, 0.06 / road_width + pixel, edge_distance);
		float lane_distance = abs(fract(u * float(lanes) + 0.5) - 0.5) / float(lanes);
		if (shoulder_m > 0.0) {
			float x = (shoulder_high_u ? u : 1.0 - u) * road_width;   // metres from the median side
			float lane_w = (road_width - shoulder_m - inner_strip_m) / float(lanes);
			float x0 = inner_strip_m, x1 = road_width - shoulder_m;
			float inner_line = abs(x - x0) / road_width;
			float outer_line = abs(x - x1) / road_width;
			float half_edge = edge_line_m * 0.5 / road_width;
			edge = max(1.0 - smoothstep(0.075 / road_width - pixel, 0.075 / road_width + pixel, inner_line),
				1.0 - smoothstep(half_edge - pixel, half_edge + pixel, outer_line));
			float lane_x = clamp((x - x0) / lane_w, 0.0, float(lanes));
			lane_distance = (x > x0 + 0.5 && x < x1 - 0.5) ? abs(fract(lane_x + 0.5) - 0.5) * lane_w / road_width : 1.0;
		}
		float half_lane_line = (shoulder_m > 0.0 ? 0.075 : 0.06) / road_width;   // 15 cm on motorways, 12 cm elsewhere
		float divider = 1.0 - smoothstep(half_lane_line - pixel, half_lane_line + pixel, lane_distance);
		float dash_v = UV.y * v_metres / dash_period;
		float dash_distance = abs(fract(dash_v) - 0.5);
		float dash_pixel = max(fwidth(dash_v) * 0.6, 0.0002);
		float half_dash = dash_fraction * 0.5;
		divider *= (1.0 - smoothstep(half_dash - dash_pixel, half_dash + dash_pixel, dash_distance)) * step(0.10, u) * step(u, 0.90);
		if (!markings) { divider = 0.0; edge = 0.0; }
		float paint_wear = mix(1.0, smoothstep(0.25, 0.65, fine), 0.35 * wear);
		base = mix(base, divider_color.rgb, divider * 0.92 * paint_wear);
		base = mix(base, vec3(0.84, 0.83, 0.78), edge * 0.92 * paint_wear);
		rough = mix(rough, 0.7, max(divider, edge) * paint_wear);
	}
	// Wet roads: darker, mirror-like where water collects (puddles in the wheel tracks first).
	float wetness = clamp(road_wetness * (dirt ? 0.7 : 1.0), 0.0, 1.0);
	base *= mix(1.0, 0.62, wetness);
	rough = mix(rough, 0.12 + 0.25 * fine, wetness);
	// Standing water in potholes once it has rained a while.
	float standing = puddle * smoothstep(0.3, 0.7, road_wetness);
	base = mix(base, base * 0.5, standing);
	rough = mix(rough, 0.04, standing);
	ALBEDO = base;
	// Dirt roads fray into the surrounding ground instead of ending on a straight line.
	float edge_m = (0.5 - abs(UV.x - 0.5)) * road_width;
	ALPHA = dirt ? edge_m / 1.1 - (fbm(world_pos.xz * 0.9) - 0.3) : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.65, wetness);
}


// Lambert with the retro lobe above, plus GGX specular (wet roads mirror lamps and headlights).
void light() {
	// A light skimming the surface (headlights reach the road at well under a degree) would pick out
	// the tiled normal map's gentle slopes as bands across the lane, one per texture repeat. At that
	// angle the grains shade each other and only the overall surface counts: the detail normal
	// fades out for grazing lights.
	vec3 gn = normalize(geo_normal);
	vec3 n = normalize(mix(gn, NORMAL, smoothstep(0.03, 0.3, dot(gn, LIGHT))));
	float ndl = clamp(dot(n, LIGHT), 0.0, 1.0);
	// Headlight beams reach the road at a fraction of a degree: plain Lambert then turns every
	// few-centimetre undulation of the surface into a bright or black band across the lane. Rough
	// aggregate catches grazing light from all sides, so the diffuse term gets a small wrap.
	float ndl_d = clamp((dot(n, LIGHT) + 0.06) / 1.06, 0.0, 1.0);
	float retro = pow(clamp(dot(LIGHT, VIEW), 0.0, 1.0), 12.0) * retro_gain;
	DIFFUSE_LIGHT += ndl_d * (1.0 + retro) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(n, h), 0.0, 1.0);
	float ndv = clamp(dot(n, VIEW), 0.001, 1.0);
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float vis = 0.25 / ((ndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
	float f0 = 0.08 * SPECULAR_AMOUNT;
	float fres = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(LIGHT, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += dist * vis * fres * ndl * ATTENUATION * LIGHT_COLOR;
}
