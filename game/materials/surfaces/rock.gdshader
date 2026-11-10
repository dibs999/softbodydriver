shader_type spatial;
// Rock for boulders and outcrops: world-space sedimentary bands (sandstone, limestone) broken up
// by noise, fine grain, dark cracks and a lighter weathered top where dust and sun bleach it.
// Works on scaled MultiMesh instances because everything is evaluated in world space.

uniform vec4 base_color : source_color = vec4(0.62, 0.40, 0.29, 1.0);
uniform vec4 band_color : source_color = vec4(0.80, 0.58, 0.42, 1.0);
uniform vec4 dark_color : source_color = vec4(0.36, 0.22, 0.16, 1.0);
uniform vec4 top_color : source_color = vec4(0.86, 0.74, 0.58, 1.0);
uniform float band_spacing = 0.9;      // metres between sediment layers
uniform float band_amount = 0.6;
uniform float crack_amount = 0.7;
uniform float top_amount = 0.45;
uniform float roughness = 0.92;
uniform float bump = 0.6;

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
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.11 + vec2(7.1, 3.3); a *= 0.5; }
	return v;
}
// Triplanar scalar noise.
float tri(vec3 p, vec3 w, float s) {
	return fbm(p.zy * s) * w.x + fbm(p.xz * s) * w.y + fbm(p.xy * s) * w.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float strata(vec3 p, float warp) {
	float y = p.y / band_spacing + warp;
	float layer = floor(y);
	float f = fract(y);
	// Layers of different thickness and tone; a thin dark seam between them.
	float tone = hash(vec2(layer, 3.7));
	float seam = 1.0 - smoothstep(0.0, 0.07, f) * smoothstep(1.0, 0.93, f);
	return tone * (1.0 - seam * 0.8) - seam * 0.35;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float warp = tri(world_pos, w, 0.35) * 1.6 + vnoise(world_pos.xz * 0.08) * 2.0;
	float s = strata(world_pos, warp);
	float grain = tri(world_pos, w, 6.0);
	float coarse = tri(world_pos, w, 1.1);
	vec3 col = mix(base_color.rgb, band_color.rgb, clamp(s, 0.0, 1.0) * band_amount);
	col = mix(col, dark_color.rgb, clamp(-s, 0.0, 1.0) * band_amount);
	col *= 0.82 + 0.36 * grain;
	col = mix(col, dark_color.rgb, smoothstep(0.62, 0.8, coarse) * 0.35);
	// Cracks: thin ridged-noise lines, mostly vertical on the faces.
	float cr = abs(vnoise(vec2(world_pos.x + world_pos.z, world_pos.y * 0.25) * 2.3) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.035, cr)) * crack_amount * (1.0 - w.y);
	col *= 1.0 - crack * 0.55;
	// Weathered, dusty tops.
	float top = smoothstep(0.55, 0.9, n.y) * top_amount * (0.6 + 0.4 * grain);
	col = mix(col, top_color.rgb, top);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness - 0.1 * grain + crack * 0.05, 0.0, 1.0);
	// Bump from the grain and the strata seams, in view space.
	float e = 0.06;
	float h0 = grain * 0.6 + s * 0.4;
	float hx = tri(world_pos + vec3(e, 0, 0), w, 6.0) * 0.6 + strata(world_pos + vec3(e, 0, 0), warp) * 0.4;
	float hy = tri(world_pos + vec3(0, e, 0), w, 6.0) * 0.6 + strata(world_pos + vec3(0, e, 0), warp) * 0.4;
	float hz = tri(world_pos + vec3(0, 0, e), w, 6.0) * 0.6 + strata(world_pos + vec3(0, 0, e), warp) * 0.4;
	vec3 g = vec3(hx - h0, hy - h0, hz - h0) / e;
	g -= n * dot(g, n);
	vec3 bn = normalize(n - g * bump * 0.08);
	NORMAL = normalize((VIEW_MATRIX * vec4(bn, 0.0)).xyz);
}
