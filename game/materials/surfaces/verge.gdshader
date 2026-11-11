shader_type spatial;
render_mode cull_disabled;
// Unpaved verge (Bankett) beside a country road: compacted grit and crumbled asphalt at the road
// edge, sparse grass growing in from the outside, and a ragged outer edge that ends in the terrain
// grass instead of a straight line. UV.x: 0 at the asphalt edge, 1 at the outer edge; UV.y in
// metres / v_metres along the road.

uniform float width_m = 1.1;
uniform float v_metres = 12.0;
uniform vec4 grit_color : source_color = vec4(0.62, 0.56, 0.47, 1.0);
uniform vec4 soil_color : source_color = vec4(0.36, 0.30, 0.22, 1.0);
uniform vec4 grass_color : source_color = vec4(0.44, 0.54, 0.24, 1.0);
global uniform float road_wetness;

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
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.07 + vec2(11.3, 7.9); a *= 0.5; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = UV.x * width_m;            // metres out from the asphalt
	float along = UV.y * v_metres;
	vec2 wp = world_pos.xz;
	// Grass reaches further in where the verge is little used.
	float reach = 0.45 + 0.6 * fbm(vec2(along * 0.09, 1.7));
	float grass = smoothstep(reach - 0.3, reach + 0.3, across + 0.45 * (fbm(wp * 2.3) - 0.5));
	// Single tufts and weeds even close to the asphalt.
	grass = max(grass, smoothstep(0.72, 0.8, vnoise(wp * 3.1 + 17.0)) * smoothstep(0.1, 0.4, across));
	// Gravel and soil: coarse grain, darker soil in hollows and wheel ruts where cars put a wheel off.
	float grain = vnoise(wp * 22.0);
	float soil = smoothstep(0.35, 0.7, fbm(wp * 0.9 + 3.0));
	vec3 base = mix(grit_color.rgb, soil_color.rgb, soil * 0.85);
	base *= 0.80 + 0.30 * grain + 0.16 * (fbm(wp * 6.0) - 0.5);
	// Stones of a few centimetres, light and dark.
	vec2 sp = wp * 16.0;
	vec2 sc = floor(sp);
	vec2 sf = fract(sp) - vec2(hash(sc), hash(sc + 4.1)) * 0.5 - 0.25;
	float stone = (1.0 - smoothstep(0.10, 0.18, length(sf))) * step(0.72, hash(sc + 9.3));
	base = mix(base, base * (0.75 + 0.5 * hash(sc + 2.0)), stone * 0.7);
	// Crumbled asphalt pieces broken off the road edge (within ~30 cm of it).
	vec2 ap = wp * 4.0;
	vec2 ac = floor(ap);
	vec2 af = fract(ap) - 0.5;
	float chunk = (1.0 - smoothstep(0.14, 0.24, length(af * vec2(1.0, 1.4)) + 0.1 * (vnoise(ap * 5.0) - 0.5)))
		* step(0.80, hash(ac + 1.3)) * (1.0 - smoothstep(0.08, 0.32, across));
	base = mix(base, vec3(0.07, 0.07, 0.075), chunk);
	// Grass: tufted, yellower in dry patches, darker blades.
	vec3 g = grass_color.rgb * (0.78 + 0.4 * vnoise(wp * 7.0));
	g = mix(g, g * vec3(1.25, 1.15, 0.7), smoothstep(0.55, 0.8, fbm(wp * 0.25)));
	float tufts = smoothstep(0.35, 0.6, vnoise(wp * 5.5) + grass * 0.6);
	base = mix(base, g, clamp(grass * tufts + grass * 0.5, 0.0, 1.0));
	// Wet: darker and a little glossy on the gravel.
	float wet = clamp(road_wetness, 0.0, 1.0);
	base *= mix(1.0, 0.7, wet);
	ALBEDO = base;
	ROUGHNESS = mix(mix(0.95, 0.75, wet), 0.9, grass);
	// Ragged outer edge: the terrain grass beneath takes over.
	ALPHA = (1.0 - UV.x) * 3.2 + 0.25 - 1.6 * fbm(wp * vec2(0.9, 0.9)) - 0.35 * vnoise(wp * 4.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
