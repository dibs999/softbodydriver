shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Car paint with crash wear. COLOR.r carries the damage mask written by SBVehicle from the plastic
// strain of the body structure (1 = intact, 0 = crushed). UV is the rest-pose box projection in
// metres, so chips and scratches stay on the panel while it deforms.
// Intact: metallic base coat under clear coat. Crushed: the clear coat cracks and dulls, paint
// flakes off to grey primer and, where worst, to scratched bare steel; creases collect grime.

uniform vec4 paint : source_color = vec4(0.62, 0.05, 0.04, 1.0);
uniform float paint_metallic = 0.5;
uniform float paint_roughness = 0.28;
uniform float clearcoat_amount = 1.0;
uniform float clearcoat_gloss = 0.08;

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
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.13 + vec2(5.2, 1.3); a *= 0.5; }
	return v;
}

void fragment() {
	float dmg = clamp(1.0 - COLOR.r, 0.0, 1.0);
	vec3 base = paint.rgb;
	float metal = paint_metallic;
	float rough = paint_roughness;
	float coat = clearcoat_amount;
	if (dmg > 0.001) {
		vec2 uv = UV;
		// Flaking: irregular islands that grow with the damage.
		float flake_n = fbm(uv * 9.0) * 0.7 + vnoise(uv * 40.0) * 0.3;
		float flaked = smoothstep(0.93, 1.02, dmg * 0.9 + flake_n * 0.55);
		float primer_edge = smoothstep(0.82, 0.93, dmg * 0.9 + flake_n * 0.55) - flaked;
		float bare = smoothstep(1.10, 1.22, dmg * 0.9 + flake_n * 0.6);
		// Scratches: thin streaks along one panel direction, more of them with damage.
		float streak = vnoise(vec2(uv.x * 3.0 + uv.y * 0.6, uv.y * 140.0));
		float scratch = smoothstep(0.88 - 0.25 * dmg, 0.93 - 0.25 * dmg, streak) * smoothstep(0.15, 0.5, dmg);
		vec3 primer = vec3(0.34, 0.34, 0.33);
		vec3 steel = vec3(0.36, 0.36, 0.38) * (0.8 + 0.35 * vnoise(uv * 80.0));
		base = mix(base, primer, clamp(primer_edge + flaked * 0.6, 0.0, 1.0));
		base = mix(base, steel, max(bare, scratch * 0.8));
		metal = mix(metal, 0.9, max(bare, scratch));
		rough = mix(rough, 0.55, clamp(flaked + primer_edge + scratch, 0.0, 1.0));
		rough = mix(rough, 0.45, bare);
		// Cracked, dull clear coat and dirt in the creases.
		coat *= 1.0 - smoothstep(0.1, 0.6, dmg);
		base *= 1.0 - 0.25 * smoothstep(0.3, 1.0, dmg) * (0.5 + 0.5 * flake_n);
		rough = mix(rough, 0.5, smoothstep(0.1, 0.6, dmg) * (1.0 - max(bare, scratch)));
	}
	ALBEDO = base;
	METALLIC = metal;
	ROUGHNESS = rough;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = clearcoat_gloss;
}
