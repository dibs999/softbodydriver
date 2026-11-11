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
			float tone = hash(vec2(layer, 1.3));
			float seam = 1.0 - smoothstep(0.0, 0.08, f) * smoothstep(1.0, 0.9, f);
			vec3 layer_col = mix(strata_dark.rgb, strata_light.rgb, tone * 0.8 + 0.2) * (1.0 - seam * 0.3);
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
		float mr = 0.11 + 0.08 * hash(mc);
		float mole = (1.0 - smoothstep(mr * 0.6, mr, length(mf) + 0.05 * (vnoise(mq * 8.0) - 0.5))) * step(0.97, hash(mc + 2.2));
		col = mix(col, vec3(0.30, 0.24, 0.17) * (0.85 + 0.3 * vnoise(q * 9.0)), mole * level);
	}
	float fine = vnoise(world_pos.xz * 1.7);
	float wet = clamp(road_wetness * wet_response, 0.0, 1.0);
	col *= mix(1.0, 0.66, wet);
	ALBEDO = col;
	ROUGHNESS = mix(roughness * mix(0.96, 1.04, fine), 0.18 + 0.3 * fine, wet * 0.85);
	SPECULAR = mix(0.5, 0.62, wet);
	if (has_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nrm), 0.0)).xyz);
	}
}
