shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
// Damaged automotive glass. UV is the generated body's rest-pose box projection in metres.
// `crack` 0..1: how far the fracture has spread over the pane. Laminated windscreens form a fine
// web of cracks held in place; tempered side glass crazes into small cubes before it falls out.

uniform vec4 tint : source_color = vec4(0.05, 0.07, 0.09, 0.42);
uniform float crack : hint_range(0.0, 1.0) = 0.5;
uniform float cell_scale = 7.0;      // coarse fracture cells per metre
uniform float fine_scale = 26.0;     // secondary crazing
uniform vec2 origin = vec2(0.0);     // UV point the fracture spreads from
uniform float seed = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed) * 43758.5453);
}

// Distance to the nearest Voronoi cell border (Inigo Quilez' two-pass formulation).
float cell_edge(vec2 x) {
	vec2 n = floor(x), f = fract(x), mg = vec2(0.0), mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++)
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	md = 8.0;
	for (int j = -2; j <= 2; j++)
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
		}
	return md;
}

float line(float d, float width) {
	float w = max(fwidth(d), 1e-4);
	return 1.0 - smoothstep(width - w, width + w, d);
}

void fragment() {
	vec2 uv = UV;
	// Spread: from the origin outwards, with a ragged front.
	float r = length(uv - origin);
	float front = crack * 1.6 + 0.12 * (hash2(floor(uv * 3.0)).x - 0.5);
	float reach = 1.0 - smoothstep(front - 0.15, front, r);
	float coarse = line(cell_edge(uv * cell_scale), 0.018);
	float fine = line(cell_edge(uv * fine_scale + 3.7), 0.03) * smoothstep(0.35, 0.9, crack);
	// Radial cracks running out from the origin.
	float ang = atan(uv.y - origin.y, uv.x - origin.x);
	float rays = line(abs(fract(ang * 2.2 + hash2(vec2(floor(ang * 2.2), 1.0)).x * 0.3) - 0.5) * r * 6.0, 0.01) * step(r, front);
	float cracks = clamp(max(max(coarse, fine * 0.8), rays), 0.0, 1.0) * reach;
	float frost = reach * crack * 0.35;
	ALBEDO = mix(tint.rgb, vec3(0.78, 0.80, 0.82), max(cracks, frost));
	ALPHA = clamp(mix(tint.a, 0.92, cracks) + frost * 0.4, 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.55, max(cracks, frost));
	METALLIC = 0.3 * (1.0 - cracks);
	SPECULAR = 0.6;
}
