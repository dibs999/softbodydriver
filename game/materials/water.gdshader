shader_type spatial;
// Still inland water (a pond, a ford): dark, slightly murky green-brown, small wind ripples in two
// directions, a Fresnel-weighted mirror of the sky through the regular specular path, and a
// lighter rim where it is shallow (the depth behind the surface, from the depth buffer).
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.05, 0.09, 0.07, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.30, 0.30, 0.20, 1.0);
uniform float clarity = 1.2;    // metres of water over which the bottom fades out
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
global uniform float road_wetness;

varying vec3 world_pos;

float hash(vec2 p) {
	p = mod(p, 512.0);
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
// Height of the ripples: two drifting layers, and rain rings when it rains.
float ripples(vec2 p, float t) {
	float h = vnoise(p * 1.7 + vec2(t * 0.35, t * 0.12)) * 0.6 + vnoise(p * 4.3 - vec2(t * 0.2, t * 0.5)) * 0.4;
	if (road_wetness > 0.05) {
		vec2 c = floor(p * 3.0);
		vec2 f = fract(p * 3.0) - 0.5;
		float phase = fract(t * 0.9 + hash(c) * 7.0);
		float ring = sin((length(f) - phase * 0.5) * 60.0) * (1.0 - phase) * step(length(f), phase * 0.5 + 0.05);
		h += ring * 0.25 * road_wetness;
	}
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float e = 0.05;
	float h0 = ripples(p, t);
	float hx = ripples(p + vec2(e, 0.0), t);
	float hz = ripples(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3(-(hx - h0) / e * 0.035, 1.0, -(hz - h0) / e * 0.035));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Water depth behind this pixel: the scene's depth buffer against the surface's own depth.
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thickness = max(0.0, length(view.xyz) - length(VERTEX));
	float shallow = 1.0 - smoothstep(0.0, clarity, thickness);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shallow * 0.8);
	ALPHA = mix(0.92, 0.35, shallow);
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
