shader_type spatial;
// Clay pantile roof on a scaled roof slab (unit box): courses of tiles in the slab's own metres,
// the rounded tile profile, a shadow line under each course, per-tile colour scatter, weathering
// and moss towards the eaves. Local x runs along the ridge, local z down the slope.

uniform vec4 base_color : source_color = vec4(0.55, 0.24, 0.16, 1.0);
uniform float tile_w = 0.30;
uniform float course = 0.34;
uniform float moss = 0.22;

varying vec3 local_m;     // position in metres along the slab axes
varying vec3 local_n;
varying vec3 world_pos;

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

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_m = VERTEX * scale;
	local_n = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = base_color.rgb;
	float rough = 0.82;
	if (local_n.y > 0.5) {
		float along = local_m.x;
		float down = local_m.z;
		float row = floor(down / course);
		float fz = fract(down / course);
		float fx = fract(along / tile_w);
		float tile = floor(along / tile_w);
		vec2 id = vec2(tile, row);
		// Rounded profile: lighter crest, darker trough.
		float profile = 0.82 + 0.26 * sin(fx * 6.2832);
		// Each course overlaps the next: a dark shadow band at its lower edge.
		float shadow = 1.0 - 0.45 * smoothstep(0.78, 1.0, fz) * (0.7 + 0.3 * sin(fx * 6.2832));
		float scatter = 0.88 + 0.24 * hash(id);
		col *= profile * shadow * scatter;
		// Weathering: dark streaks running down the slope, sooty blotches.
		col *= 0.88 + 0.12 * vnoise(vec2(along * 1.3, down * 0.15));
		// Moss and lichen in patches, thickest in the overlaps where water lingers.
		float m = smoothstep(0.7, 0.86, vnoise(world_pos.xz * 2.2 + id * 0.3)) * moss;
		col = mix(col, vec3(0.17, 0.20, 0.09), m * (0.5 + 0.5 * fz));
		rough = 0.78 + 0.15 * hash(id + 3.0);
	} else {
		col *= 0.75;   // cut edges of the slab: the tile ends in shadow
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
