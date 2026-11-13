shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Car paint with crash wear. COLOR.r carries the damage mask written by SBVehicle from the plastic
// strain of the body structure (1 = intact, 0 = crushed). UV is the rest-pose box projection in
// metres, so chips and scratches stay on the panel while it deforms.
// Intact: metallic base coat under clear coat. Crushed: the clear coat cracks and dulls, paint
// flakes off to grey primer and, where worst, to scratched bare steel; creases collect grime.

uniform vec4 paint : source_color = vec4(0.62, 0.05, 0.04, 1.0);
// Imported shells model the pillars with thickness, so their inner faces are body paint and the
// A-pillars glared red from the driver's seat. When cabin_on, painted faces inside the cabin
// (a box round the driver's eye in the car's axes) that face into it are drawn as dark trim.
uniform bool cabin_on = false;
uniform vec3 cabin_eye = vec3(0.0);
uniform vec3 cabin_fwd = vec3(1.0, 0.0, 0.0);
uniform vec3 cabin_up = vec3(0.0, 1.0, 0.0);
uniform vec3 cabin_mid = vec3(0.0);   // a point on the car's centre line (lateral reference)
uniform float paint_metallic = 0.5;
uniform float paint_roughness = 0.28;
uniform float clearcoat_amount = 1.0;
uniform float clearcoat_gloss = 0.08;
// Dirt from driving on loose ground (set by vehicle_effects.gd): worst low down, splattered upwards.
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dirt_color : source_color = vec4(0.36, 0.28, 0.19, 1.0);

float hash(vec2 p) {
	p = mod(p, 512.0);   // world coordinates of a few km would leave the fract below without precision
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
		// Even a badly crushed panel keeps most of its paint: at full damage about a quarter flakes to
		// primer and a tenth to bare steel, in islands (whole wings used to turn to bare metal).
		float flaked = smoothstep(1.02, 1.08, dmg * 0.75 + flake_n * 0.55);
		float primer_edge = smoothstep(0.92, 1.02, dmg * 0.75 + flake_n * 0.55) - flaked;
		float bare = smoothstep(1.13, 1.20, dmg * 0.75 + flake_n * 0.6);
		// Scratches: thin streaks along one panel direction, more of them with damage.
		float streak = vnoise(vec2(uv.x * 3.0 + uv.y * 0.6, uv.y * 140.0));
		float scratch = smoothstep(0.93 - 0.10 * dmg, 0.96 - 0.10 * dmg, streak) * smoothstep(0.15, 0.5, dmg);
		vec3 primer = vec3(0.34, 0.34, 0.33);
		vec3 steel = vec3(0.36, 0.36, 0.38) * (0.8 + 0.35 * vnoise(uv * 80.0));
		base = mix(base, primer, clamp(primer_edge + flaked * 0.6, 0.0, 1.0));
		base = mix(base, steel, max(bare, scratch * 0.8));
		metal = mix(metal, 0.75, max(bare, scratch));
		rough = mix(rough, 0.55, clamp(flaked + primer_edge + scratch, 0.0, 1.0));
		rough = mix(rough, 0.55, bare);
		// Cracked, dull clear coat and dirt in the creases.
		coat *= 1.0 - smoothstep(0.1, 0.6, dmg);
		base *= 1.0 - 0.25 * smoothstep(0.3, 1.0, dmg) * (0.5 + 0.5 * flake_n);
		rough = mix(rough, 0.5, smoothstep(0.1, 0.6, dmg) * (1.0 - max(bare, scratch)));
	}
	if (dirt_amount > 0.001) {
		float h = COLOR.g;   // 0 at the sill, 1 at the roof
		float splat = fbm(UV * 7.0 + vec2(3.0, 1.0)) * 0.6 + vnoise(UV * 35.0) * 0.4;
		float reach = dirt_amount * 0.9;   // how far up the body the dirt has climbed
		float mask = smoothstep(reach * 0.75 + 0.05, reach * 0.75 - 0.25, h + (splat - 0.5) * 0.35);
		mask = clamp(mask * smoothstep(0.0, 0.25, dirt_amount) + dirt_amount * 0.15 * splat, 0.0, 1.0);
		base = mix(base, dirt_color.rgb * (0.8 + 0.4 * splat), mask * 0.9);
		rough = mix(rough, 0.92, mask);
		metal = mix(metal, 0.0, mask);
		coat *= 1.0 - mask;
	}
	if (cabin_on) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 right = normalize(cross(cabin_fwd, cabin_up));
		vec3 d = wp - cabin_eye;
		float along = dot(d, cabin_fwd), up = dot(d, cabin_up), side = dot(wp - cabin_mid, right);
		// From behind the rear seats to the foot of the A-pillars, belt line to roof, full width.
		bool inside = along > -1.7 && along < 0.95 && up > -0.24 && up < 0.6 && abs(side) < 0.98;
		// Ahead of the eye only faces that are not mostly upward (pillars, not the scuttle/bonnet).
		inside = inside && (along < 0.3 || dot(wn, cabin_up) < 0.45);
		vec3 centre = cabin_eye - cabin_fwd * 0.45 + cabin_up * 0.05 + right * dot(cabin_mid - cabin_eye, right);
		if (inside && dot(wn, centre - wp) > 0.0) {
			base = vec3(0.085, 0.085, 0.09);
			metal = 0.0;
			rough = 0.92;
			coat = 0.0;
		}
	}
	ALBEDO = base;
	METALLIC = metal;
	ROUGHNESS = rough;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = clearcoat_gloss;
}
