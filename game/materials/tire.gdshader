shader_type spatial;
// Tyre of a procedural wheel. The mesh is built round the wheel axle (local z) without UVs, so
// the pattern comes from the local position: transverse sipes in a directional pattern across the
// tread, and on the sidewall a rim-protector ring and a band of raised lettering. It rotates with
// the wheel because the wheel instance does. Radii come per instance from the vehicle; without
// them (0) the material is plain rubber.

instance uniform float tire_radius = 0.0;
instance uniform float rim_radius = 0.0;
instance uniform float tire_width = 0.205;
instance uniform float block_tread = 0.0;   // 1: all-terrain block tread, "TERRA" on the sidewall
uniform vec4 rubber : source_color = vec4(0.035, 0.035, 0.037, 1.0);
global uniform float road_wetness;

// Sidewall lettering: a 5 x 5 pixel font (rows top to bottom, 5 bits each, leftmost bit high)
// and the texts as glyph indices.
// Glyphs: space V E L T R A S P O 2 0 5 / 1 6 9 M + 3 4 7 8.
const int GLYPHS[23] = int[](0, 18400580, 33061407, 17318431, 32641156, 32045714, 15269425, 16267326, 32045584, 15255086, 31504927, 15324974, 33060926, 1118480, 4591758, 15235630, 15252526, 18732593, 145536,
	31504446, 19496002, 32575752, 15252014);
const int DIGIT[10] = int[](11, 14, 10, 19, 20, 12, 15, 21, 22, 16);
const int TEXT_BRAND[12] = int[](1, 2, 3, 4, 5, 6, 0, 7, 8, 9, 5, 4);        // VELTRA SPORT
const int TEXT_TERRA[12] = int[](1, 2, 3, 4, 5, 6, 0, 4, 2, 5, 5, 6);        // VELTRA TERRA
const int TEXT_MS[3] = int[](17, 18, 7);

varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec2 p) {
	p = mod(p, 512.0);   // world coordinates of a few km would leave the fract below without precision
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


// 1 inside a raised pixel of character `ch` at cell coordinates f (0..1, y = 0 at the top).
float glyph_pixel(int ch, vec2 f) {
	if (f.x < 0.0 || f.x >= 1.0 || f.y < 0.0 || f.y >= 1.0) return 0.0;
	int col = int(f.x * 6.0);          // 5 pixel columns plus one column of spacing
	int row = int(f.y * 5.0);
	if (col > 4) return 0.0;
	int bits = GLYPHS[ch];
	return float((bits >> ((4 - row) * 5 + (4 - col))) & 1);
}

// Character k of the size marking "WWW/PP RDD 91V", from the tyre's own dimensions: width in mm
// (5 mm steps), profile in % of the width (5 % steps), rim diameter in inches.
int size_char(int k) {
	int w = int(round(tire_width * 200.0)) * 5;
	int p = clamp(int(round((tire_radius - rim_radius) / max(tire_width, 0.05) * 20.0)) * 5, 10, 95);
	int d = clamp(int(round(rim_radius * 2.0 / 0.0254)), 10, 24);
	if (k == 0) return DIGIT[(w / 100) % 10];
	if (k == 1) return DIGIT[(w / 10) % 10];
	if (k == 2) return DIGIT[w % 10];
	if (k == 3) return 13;
	if (k == 4) return DIGIT[(p / 10) % 10];
	if (k == 5) return DIGIT[p % 10];
	if (k == 6) return 0;
	if (k == 7) return 5;
	if (k == 8) return DIGIT[(d / 10) % 10];
	if (k == 9) return DIGIT[d % 10];
	if (k == 10) return 0;
	if (k == 11) return 16;
	if (k == 12) return 14;
	return 1;
}

// The text at arc position s (metres from the start of the run), cell width cw: the glyph pixel.
float text_at(float s, float fy, float cw, int which) {
	int n = which == 0 ? 12 : (which == 1 ? 14 : 3);
	float ci = floor(s / cw);
	if (ci < 0.0 || ci >= float(n)) return 0.0;
	int k = int(ci);
	int ch = which == 0 ? (block_tread > 0.5 ? TEXT_TERRA[k] : TEXT_BRAND[k]) : (which == 1 ? size_char(k) : TEXT_MS[k]);
	return glyph_pixel(ch, vec2(fract(s / cw), fy));
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
		if (block_tread > 0.5) {
			// All-terrain: big staggered blocks (about 5.5 cm along, three rows across) with wide
			// voids between them; the shoulder blocks reach round onto the sidewall.
			float zr = local_pos.z / max(tire_width, 0.05) + 0.5;   // 0..1 across the tread
			float row = floor(clamp(zr, 0.0, 0.999) * 3.0);
			float u = fract((along + row * 0.018) / 0.055);
			float v = fract(clamp(zr, 0.0, 0.999) * 3.0);
			groove = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.66, 0.74, u)) * smoothstep(0.0, 0.1, v) * (1.0 - smoothstep(0.86, 0.96, v));
			tread = max(tread, (1.0 - smoothstep(0.75, 0.95, axial)) * smoothstep(tire_radius - 0.045, tire_radius - 0.02, r)
				* smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.62, 0.7, u)));
		}
		col *= mix(1.0, mix(block_tread > 0.5 ? 0.25 : 0.45, 1.05, groove), tread);
		rough = mix(rough, mix(0.97, 0.84, groove), tread);
		// Sidewall: 0 at the rim, 1 at the shoulder.
		float side = smoothstep(0.6, 0.85, axial);
		float t = (r - rim_radius) / max(tire_radius - rim_radius, 0.01);
		float protector = smoothstep(0.10, 0.13, t) * (1.0 - smoothstep(0.16, 0.19, t));
		// Lettering round each sidewall: the brand in large letters, then the size and load index
		// and an M+S mark in smaller ones; read the right way round on both sides.
		float rm = rim_radius + 0.6 * (tire_radius - rim_radius);
		float a = local_pos.z < 0.0 ? ang : -ang;
		float s_arc = fract(a / 6.2831853) * 6.2831853 * rm;   // metres along the sidewall
		float big_lo = 0.40, big_hi = 0.80, small_lo = 0.50, small_hi = 0.72;
		float fy_big = 1.0 - (t - big_lo) / (big_hi - big_lo);
		float fy_small = 1.0 - (t - small_lo) / (small_hi - small_lo);
		float cw_big = (big_hi - big_lo) * (tire_radius - rim_radius) * 1.15;
		float cw_small = (small_hi - small_lo) * (tire_radius - rim_radius) * 1.15;
		float strokes = text_at(s_arc - 0.04, fy_big, cw_big, 0);
		float size_start = 0.04 + 13.0 * cw_big;
		strokes = max(strokes, text_at(s_arc - size_start, fy_small, cw_small, 1));
		strokes = max(strokes, text_at(s_arc - size_start - 16.0 * cw_small, fy_small, cw_small, 2));
		float cell_u = s_arc / cw_small;
		float band = 1.0;
		float word = 1.0;
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
