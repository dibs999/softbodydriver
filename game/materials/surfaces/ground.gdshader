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
	// Large patches in world space: lighter/darker batches, dry or lush areas.
	vec2 mp = world_pos.xz / macro_scale;
	float macro = fbm(mp);
	float patches = smoothstep(0.48, 0.68, fbm(mp * 0.61 + vec2(17.0, 3.0)));
	col *= mix(1.0 - macro_strength, 1.0 + macro_strength, macro);
	col = mix(col, col * macro_tint.rgb * 1.6, patches * macro_tint_amount);
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
