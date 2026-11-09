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
	vec2 d = uv - origin;
	float r = length(d);
	// The fracture spreads from the origin; even a crazed screen keeps clear areas far from it.
	float front = 0.18 + crack * 0.95;
	float ragged = 0.10 * (hash2(floor(uv * 4.0)).x - 0.5);
	float reach = 1.0 - smoothstep(front - 0.2, front + ragged, r);
	// Spider web at the origin: radial cracks and concentric rings, denser close in.
	float ang = atan(d.y, d.x) / 6.28318 + 0.5;
	float spokes = 15.0;
	float sector = floor(ang * spokes);
	float wobble = 0.15 * sin(r * 23.0 + sector * 1.7) * smoothstep(0.0, 0.3, r);
	float radial = abs(fract(ang * spokes + wobble) - 0.5) * r * 6.28318 / spokes;   // metres to spoke
	float spoke_len = front * (0.55 + 0.45 * hash2(vec2(sector, 3.0)).x);
	float spokes_mask = line(radial, 0.0009) * step(r, spoke_len);
	float ring_r = r * (9.0 - 4.0 * smoothstep(0.0, 0.8, r)) + hash2(vec2(sector, 7.0)).x;
	float rings = line(abs(fract(ring_r) - 0.5) / 9.0, 0.0008) * step(0.03, r) * step(r, front * 0.8)
		* step(0.35, hash2(vec2(sector, floor(ring_r))).x);
	// Crazing: tempered glass breaks into small cells; laminated glass only right at the impact.
	float craze_area = mix(0.12, front, step(0.5, cell_scale / 10.0)) * (0.4 + 0.6 * crack);
	float fine = line(cell_edge(uv * fine_scale + 3.7) / fine_scale, 0.0007) * (1.0 - smoothstep(craze_area * 0.6, craze_area, r));
	float coarse = line(cell_edge(uv * cell_scale) / cell_scale, 0.0011) * smoothstep(0.55, 1.0, crack);
	float cracks = clamp(max(max(spokes_mask, rings), max(fine, coarse * 0.8)), 0.0, 1.0) * reach;
	// Powdered glass right at the impact point.
	float star = (1.0 - smoothstep(0.0, 0.035 + 0.04 * crack, r)) * crack;
	float white = max(cracks * 0.85, star);
	ALBEDO = mix(tint.rgb, vec3(0.80, 0.82, 0.84), white);
	ALPHA = clamp(mix(tint.a, 0.85, white), 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.5, white);
	METALLIC = 0.3 * (1.0 - white);
	SPECULAR = 0.6;
}
