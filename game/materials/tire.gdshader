shader_type spatial;
// Tyre of a procedural wheel. The mesh is built round the wheel axle (local z) without UVs, so
// the pattern comes from the local position: transverse sipes in a directional pattern across the
// tread, and on the sidewall a rim-protector ring and a band of raised lettering. It rotates with
// the wheel because the wheel instance does. Radii come per instance from the vehicle; without
// them (0) the material is plain rubber.

instance uniform float tire_radius = 0.0;
instance uniform float rim_radius = 0.0;
uniform vec4 rubber : source_color = vec4(0.035, 0.035, 0.037, 1.0);
global uniform float road_wetness;

varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec2 p) {
	p = mod(p, 512.0);   // world coordinates of a few km would leave the fract below without precision
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 col = rubber.rgb;
	float rough = 0.9;
	if (tire_radius > 0.0) {
		float r = length(local_pos.xy);
		float ang = atan(local_pos.y, local_pos.x);
		float axial = abs(normalize(local_normal).z);
		// Tread: radial faces near the outer radius. Sipes run across at an angle that flips at
		// the centre line (a directional V), every 3.2 cm of circumference.
		float tread = (1.0 - smoothstep(0.45, 0.7, axial)) * smoothstep(tire_radius - 0.025, tire_radius - 0.006, r);
		float along = ang * tire_radius;
		float sipe = fract((along + abs(local_pos.z) * 0.55) / 0.032);
		float groove = smoothstep(0.0, 0.07, sipe) * (1.0 - smoothstep(0.86, 0.93, sipe));
		col *= mix(1.0, mix(0.45, 1.05, groove), tread);
		rough = mix(rough, mix(0.97, 0.84, groove), tread);
		// Sidewall: 0 at the rim, 1 at the shoulder.
		float side = smoothstep(0.6, 0.85, axial);
		float t = (r - rim_radius) / max(tire_radius - rim_radius, 0.01);
		float protector = smoothstep(0.10, 0.13, t) * (1.0 - smoothstep(0.16, 0.19, t));
		// Lettering: two words per side, each a row of 2 cm character cells with random strokes.
		float band = smoothstep(0.46, 0.49, t) * (1.0 - smoothstep(0.70, 0.73, t));
		float turn = fract(ang / 6.2831853 * 2.0);
		float word = step(0.06, turn) * step(turn, 0.34) + step(0.56, turn) * step(turn, 0.70);
		float cell_u = ang * r / 0.02;
		vec2 cell = vec2(floor(cell_u), floor(ang / 3.14159265));
		vec2 f = vec2(fract(cell_u), (t - 0.49) / 0.21);
		float strokes = 0.0;
		for (int k = 0; k < 3; k++) {
			float h = hash(cell + float(k) * 7.1);
			// vertical, horizontal or diagonal stroke in the cell
			float d = h < 0.4 ? abs(f.x - (0.2 + 0.6 * hash(cell + float(k) * 3.3)))
				: h < 0.75 ? abs(f.y - (0.15 + 0.7 * hash(cell + float(k) * 5.9))) * 0.6
				: abs((f.x - 0.5) - (f.y - 0.5) * (hash(cell + 2.0) > 0.5 ? 1.0 : -1.0)) * 0.7;
			strokes = max(strokes, 1.0 - smoothstep(0.09, 0.14, d));
		}
		// Fade the lettering out where a character cell shrinks below a few pixels (no shimmer).
		float detail = 1.0 - smoothstep(0.15, 0.35, fwidth(cell_u));
		float lettering = strokes * band * word * detail;
		float raised = max(protector, lettering) * side;
		col = mix(col, col * 1.6 + vec3(0.006), raised);
		rough = mix(rough, 0.72, raised);
	}
	float wet = clamp(road_wetness, 0.0, 1.0);
	ALBEDO = col * mix(1.0, 0.8, wet);
	ROUGHNESS = mix(rough, 0.35, wet * 0.6);
	SPECULAR = 0.35;
}
