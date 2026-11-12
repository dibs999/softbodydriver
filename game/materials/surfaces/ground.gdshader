shader_type spatial;
// Ground and paving: world-space triplanar texturing with anti-tiling, large-scale tone
// variation (patches, bleaching, dry grass) and weather wetness. No UVs or tangents needed.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_strength = 0.3;
uniform float tile_metres = 2.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float roughness = 0.9;
uniform float macro_strength = 0.12;      // brightness variation of the large patches
uniform float macro_scale = 38.0;         // metres per patch
uniform vec4 macro_tint : source_color = vec4(1.0);  // colour of the "other" patches
uniform float macro_tint_amount = 0.0;
uniform float wet_response = 1.0;         // 1 = sealed surface (dark, glossy when wet)
// Terrain only: bare earth and stone showing through on steep ground (embankments, hillsides).
uniform sampler2D slope_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_slope = false;
uniform float slope_tile = 3.0;
uniform vec4 slope_tint : source_color = vec4(1.0);
uniform float slope_start = 0.90;         // normal.y at which earth starts to show
uniform float slope_full = 0.72;          // normal.y of fully bare ground
// Desert: sedimentary layers on steep faces (mesa walls, road cuts) instead of plain earth.
uniform bool has_strata = false;
uniform float strata_spacing = 1.4;
uniform vec4 strata_light : source_color = vec4(0.92, 0.70, 0.52, 1.0);
uniform vec4 strata_dark : source_color = vec4(0.52, 0.30, 0.21, 1.0);
// Grass terrain: mid-scale lush/dry patches, clover clumps, wildflower clusters and molehills.
uniform bool meadow = false;
// City carriageway: a grid of streets (x/z origin, pitch, street width; pitch 0 = off) gets the
// wear of a real town street: polished wheel tracks per lane, oil drips, utility trenches filled
// with fresher asphalt, a crack network sealed with bitumen in places and a dirty gutter.
uniform vec4 street_grid = vec4(0.0);
uniform float street_lane = 4.0;
global uniform float road_wetness;

varying vec3 world_pos;
varying vec3 world_normal;

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

// Distance to the nearest Voronoi cell border (crack network).
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

// Street wear for one street direction. across: metres from the centre line; along: metres
// along the street; street_id: which street of the grid. Returns (darken, gloss, lighten, oil).
vec4 street_wear(float across, float along, float street_id, float width, float junction) {
	float a = abs(across);
	float half_w = width * 0.5;
	vec4 r = vec4(0.0);
	// Wheel tracks: each lane centre +-0.78 m, polished darker and smoother; faint at junctions.
	float lane_c = mod(a, street_lane) - street_lane * 0.5;
	float track_d = abs(abs(lane_c) - 0.78);
	float tracks = (1.0 - smoothstep(0.12, 0.38, track_d)) * (1.0 - junction * 0.7);
	tracks *= mix(0.6, 1.0, vnoise(vec2(along * 0.05, street_id * 3.1)));
	r.x += tracks * 0.2;
	r.y += tracks * 0.25;
	// Oil drips down the lane centres, densest where cars queue before a junction.
	vec2 oc = floor(vec2(along / 0.9, lane_c * 2.0 + street_id * 7.0));
	vec2 of = fract(vec2(along / 0.9, 0.5)) - vec2(hash(oc), 0.5);
	float oil = (1.0 - smoothstep(0.03, 0.13, length(vec2(of.x * 0.9, lane_c * 1.6 + (hash(oc + 4.0) - 0.5) * 0.4)))) * step(0.72 - junction * 0.25, hash(oc + 9.0));
	r.w += oil;
	// Utility trenches: long strips of fresher, darker asphalt along a lane (cables, pipes), with
	// lighter sawn seams, and the odd transverse cut right across.
	float seg = floor(along / 23.0);
	float pick = hash(vec2(seg, street_id + 1.3));
	float t_pos = (hash(vec2(seg, street_id + 5.1)) - 0.5) * (width - 2.5);
	float t_w = 0.55 + 0.5 * hash(vec2(seg, street_id + 8.2));
	float t_along = fract(along / 23.0);
	float t_len = 0.25 + 0.6 * hash(vec2(seg, street_id + 2.7));
	float in_len = step(0.05, t_along) * step(t_along, 0.05 + t_len);
	float d_t = abs(across - t_pos) - t_w * 0.5;
	float trench = (1.0 - smoothstep(-0.005, 0.005, d_t)) * in_len * step(0.62, pick);
	float seam = (1.0 - smoothstep(0.0, 0.035, abs(d_t))) * in_len * step(0.62, pick);
	float cross_cut = step(0.86, hash(vec2(seg, street_id + 11.0)));
	float cut_d = abs(t_along - 0.7) * 23.0 - 0.45;
	float cut = (1.0 - smoothstep(-0.005, 0.005, cut_d)) * step(a, half_w) * cross_cut;
	float cut_seam = (1.0 - smoothstep(0.0, 0.035, abs(cut_d))) * cross_cut;
	r.x += max(trench, cut) * 0.32;
	r.y -= max(trench, cut) * 0.12;
	r.z += max(seam, cut_seam) * 0.5;
	// Gutter: the last ~40 cm before the kerb collects grit and water stains.
	float gutter = 1.0 - smoothstep(0.1, 0.5, half_w - a);
	r.z += gutter * 0.35 * smoothstep(0.0, 0.1, half_w - a);
	return r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Two samples at different scale and rotation, blended by low-frequency noise: hides the
// repeat of the photo texture at the distances where it otherwise forms a visible grid.
vec4 sample_anti_tile(sampler2D tex, vec2 uv, float mask) {
	vec4 a = texture(tex, uv);
	vec2 r = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * uv * 0.43 + vec2(0.37, 0.71);
	vec4 b = texture(tex, r);
	return mix(a, b, mask);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos / tile_metres;
	float mask = smoothstep(0.35, 0.65, vnoise(world_pos.xz * 0.045 + world_pos.y * 0.03));
	vec3 col = vec3(0.0);
	vec3 nrm = vec3(0.0);
	if (w.x > 0.01) {
		col += sample_anti_tile(albedo_tex, p.zy, mask).rgb * w.x;
		if (has_normal) {
			vec2 t = (sample_anti_tile(normal_tex, p.zy, mask).rg * 2.0 - 1.0) * normal_strength;
			nrm += vec3(t + n.zy, n.x).zyx * w.x;
		}
	}
	if (w.y > 0.01) {
		col += sample_anti_tile(albedo_tex, p.xz, mask).rgb * w.y;
		if (has_normal) {
			vec2 t = (sample_anti_tile(normal_tex, p.xz, mask).rg * 2.0 - 1.0) * normal_strength;
			t.y = -t.y;
			nrm += vec3(t + n.xz, n.y).xzy * w.y;
		}
	}
	if (w.z > 0.01) {
		col += sample_anti_tile(albedo_tex, p.xy, mask).rgb * w.z;
		if (has_normal) {
			vec2 t = (sample_anti_tile(normal_tex, p.xy, mask).rg * 2.0 - 1.0) * normal_strength;
			nrm += vec3(t + n.xy, n.z) * w.z;
		}
	}
	col *= tint.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	if (has_slope) {
		float steep = 1.0 - smoothstep(slope_full, slope_start, n.y);
		float breakup = fbm(world_pos.xz * 0.19 + vec2(5.0, 9.0));
		steep = clamp(steep * 1.35 - (breakup - 0.5) * 1.3, 0.0, 1.0);
		vec3 ps = world_pos / slope_tile;
		vec3 earth = texture(slope_tex, ps.zy).rgb * w.x + texture(slope_tex, ps.xz).rgb * w.y + texture(slope_tex, ps.xy).rgb * w.z;
		if (has_strata) {
			float warp = fbm(world_pos.xz * 0.02) * 4.0 + vnoise(world_pos.xz * 0.15) * 0.6;
			float y = world_pos.y / strata_spacing + warp;
			float layer = floor(y);
			float f = fract(y);
			// Thick beds whose colour drifts gradually from one to the next (sandstone is laid down
			// in sequences, not alternating stripes), fine lamination inside each layer and only
			// faint seams.
			float bed = smoothstep(0.2, 0.8, vnoise(vec2(y * 0.45, 1.3)));
			float tone = mix(bed, hash(vec2(layer, 1.3)), 0.3);
			float seam = 1.0 - smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f);
			float lamina = 0.94 + 0.06 * sin(y * 25.1327 + vnoise(world_pos.xz * 0.3) * 3.0);
			vec3 layer_col = mix(strata_dark.rgb, strata_light.rgb, 0.3 + 0.7 * tone) * (1.0 - seam * 0.2) * lamina;
			// Vertical erosion streaks (desert varnish) running down the faces.
			float streak = vnoise(vec2((world_pos.x + world_pos.z) * 0.9, world_pos.y * 0.04));
			layer_col *= 0.86 + 0.24 * streak;
			earth = mix(earth, vec3(dot(earth, vec3(0.33))), 0.6) * 1.6 * layer_col;
		}
		col = mix(col, earth * slope_tint.rgb, steep);
	}
	// Large patches in world space: lighter/darker batches, dry or lush areas.
	vec2 mp = world_pos.xz / macro_scale;
	float macro = fbm(mp);
	float patches = smoothstep(0.48, 0.68, fbm(mp * 0.61 + vec2(17.0, 3.0)));
	col *= mix(1.0 - macro_strength, 1.0 + macro_strength, macro);
	col = mix(col, col * macro_tint.rgb * 1.6, patches * macro_tint_amount);
	if (meadow) {
		vec2 q = world_pos.xz;
		float level = smoothstep(0.86, 0.96, n.y);
		// Lush (darker, bluer green) and dry (yellower) patches of a few metres.
		float mid = fbm(q * 0.16 + vec2(31.0, 4.0));
		col *= mix(vec3(0.80, 0.92, 0.76), vec3(1.17, 1.08, 0.80), smoothstep(0.3, 0.75, mid));
		// Dense clover / sedge clumps.
		float clump = smoothstep(0.62, 0.82, vnoise(q * 1.3 + 7.0));
		col *= 1.0 - clump * 0.16;
		// Wildflowers in clusters; beyond the distance a flower is a few pixels they become a tint.
		float px = length(fwidth(q));
		float near = 1.0 - smoothstep(0.015, 0.05, px);
		float cluster = smoothstep(0.5, 0.85, fbm(q * 0.33 + vec2(3.0, 8.0)));
		vec2 fp = q * 6.5;
		vec2 fc = floor(fp);
		vec2 ff = fract(fp) - vec2(hash(fc), hash(fc + 1.7)) * 0.6 - 0.2;
		float flower = (1.0 - smoothstep(0.13, 0.22, length(ff))) * step(0.94 - cluster * 0.4, hash(fc + 4.4));
		float sort = hash(fc + 9.1);
		vec3 petal = sort < 0.45 ? vec3(0.92, 0.92, 0.86) : (sort < 0.8 ? vec3(0.93, 0.80, 0.18) : vec3(0.58, 0.45, 0.82));
		col = mix(col, petal * 0.85, flower * near * level);
		col = mix(col, col * vec3(1.16, 1.10, 0.78), cluster * (1.0 - near) * 0.5 * level);
		// Molehills and bare spots.
		vec2 mq = q / 3.0;
		vec2 mc = floor(mq);
		vec2 mf = fract(mq) - 0.5;
		float mr = 0.07 + 0.05 * hash(mc);
		float mole = (1.0 - smoothstep(mr * 0.6, mr, length(mf) + 0.05 * (vnoise(mq * 8.0) - 0.5))) * step(0.97, hash(mc + 2.2));
		col = mix(col, vec3(0.13, 0.10, 0.07) * (0.85 + 0.3 * vnoise(q * 9.0)), mole * level);
	}
	float street_gloss = 0.0;
	if (street_grid.z > 0.0) {
		float pitch = street_grid.z, width = street_grid.w;
		vec2 l = world_pos.xz - street_grid.xy;
		vec2 lm = mod(l, pitch);
		vec2 sid = floor(l / pitch);
		bool along_x = lm.y < width;   // a street running along x (fixed z band)
		bool along_z = lm.x < width;
		float junction = along_x && along_z ? 1.0 : 0.0;
		vec4 wear = vec4(0.0);
		if (along_x) wear += street_wear(lm.y - width * 0.5, world_pos.x, sid.y + 0.37, width, junction);
		if (along_z) wear += street_wear(lm.x - width * 0.5, world_pos.z, sid.x + 50.21, width, junction);
		if (along_x || along_z) {
			col *= 1.0 - clamp(wear.x, 0.0, 0.5);
			col = mix(col, col * vec3(1.22, 1.17, 1.08) + vec3(0.025, 0.022, 0.016), clamp(wear.z, 0.0, 1.0) * 0.6);
			col = mix(col, col * 0.5, clamp(wear.w, 0.0, 1.0) * 0.75);
			// Ageing: a crack network in worn stretches, black bitumen sealing over some cracks.
			vec2 wp = world_pos.xz;
			float aged = smoothstep(0.42, 0.6, fbm(wp * 0.02 + vec2(41.0, 7.0)));
			// Both networks cost ~30 noise lookups, so they only run where they can show.
			float crack = 0.0;
			float cw = max(length(fwidth(wp)) * 0.7, 0.001);   // derivatives outside the branches
			if (aged > 0.0) {
				vec2 warp = vec2(fbm(wp * 0.35), fbm(wp * 0.35 + 9.0)) - 0.5;
				float ce = cell_edge((wp + warp * 1.4) / 1.3) * 1.3;
				crack = (1.0 - smoothstep(0.005, 0.005 + cw, ce)) * aged * smoothstep(0.4, 0.55, vnoise(wp * 0.45 + 3.0));
			}
			float seal = 0.0;
			float seal_zone = smoothstep(0.58, 0.7, vnoise(wp * 0.04 + 13.0)) * step(0.45, vnoise(wp * 0.45 + 5.0));
			if (seal_zone > 0.0) {
				float seal_line = cell_edge(wp / 4.0 + 7.0) * 4.0 + 0.05 * (vnoise(wp * 3.0) - 0.5);
				seal = (1.0 - smoothstep(0.016, 0.016 + cw * 1.5, seal_line)) * seal_zone;
			}
			col = mix(col, col * 0.45, crack * 0.85);
			col = mix(col, vec3(0.018), seal * 0.9);
			street_gloss = clamp(wear.y, -0.2, 0.4) + seal * 0.15 + clamp(wear.w, 0.0, 1.0) * 0.2;
		}
	}
	float fine = vnoise(world_pos.xz * 1.7);
	float wet = clamp(road_wetness * wet_response, 0.0, 1.0);
	col *= mix(1.0, 0.66, wet);
	ALBEDO = col;
	ROUGHNESS = mix(roughness * mix(0.96, 1.04, fine) * (1.0 - street_gloss), 0.18 + 0.3 * fine, wet * 0.85);
	SPECULAR = mix(0.5, 0.62, wet);
	if (has_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nrm), 0.0)).xyz);
	}
}
