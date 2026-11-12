shader_type spatial;
// Rain on the windscreen: refractive drops that build up with exposure and are cleared where the
// wiper blades have passed. UV2 carries metric glass coordinates (lateral, along the glass), so
// drops stay round on the trapezoidal pane. The wiper motion is evaluated analytically from the
// cycle counter: blade angle = parked - sweep * (1 - cos(2 pi phase)) / 2.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float rain = 0.0;          // 0 dry .. 1 heavy rain (drop formation rate)
uniform float wetness = 0.0;       // drops linger while the surface dries
uniform float cycles = 0.0;        // wiper cycles since activation
uniform float period = 1.2;
uniform float off_time = 0.0;      // seconds since the blades parked (0 while running)
uniform float pre_time = 1000.0;   // unwiped seconds before this activation
uniform float sweep = 1.75;
uniform vec2 pivot_a;
uniform vec2 pivot_b;
uniform vec2 radius_a;             // blade inner/outer radius
uniform vec2 radius_b;
// Metres the drops of each layer have run along the glass (+ up: airflow above ~55 km/h, - down:
// gravity when slow), and how far they are drawn out into streaks by the airflow (0 .. 1).
uniform float flow_a = 0.0;
uniform float flow_b = 0.0;
uniform float stretch = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Seconds since the blade around `pivot` last passed point m (large if outside its arc).
float since_wiped(vec2 m, vec2 pivot, vec2 radius) {
	vec2 r = m - pivot;
	float len = length(r);
	float phi = 3.14159265 - atan(r.y, r.x);   // 0 when parked (pointing along -lateral)
	if (r.y < 0.0 || len < radius.x || len > radius.y || phi > sweep) {
		return 1e5;
	}
	float ph1 = acos(clamp(1.0 - 2.0 * phi / sweep, -1.0, 1.0)) / 6.2831853;
	float ph2 = 1.0 - ph1;
	if (cycles < ph1) {
		return cycles * period + pre_time + ph1 * period + off_time;
	}
	float last = floor(cycles) + (fract(cycles) >= ph2 ? ph2 : (fract(cycles) >= ph1 ? ph1 : ph2 - 1.0));
	return (cycles - last) * period + off_time;
}

// One layer of drops on a grid of `cell` metres. Returns refraction offset (xy) and coverage (z).
vec3 drops(vec2 m, float cell, float since, float seed, float streak) {
	vec2 g = m / cell;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id + seed);
	if (h > 0.55) {
		return vec3(0.0);    // empty cells keep gaps between drops
	}
	// Drops form one after another; heavier rain fills the glass sooner.
	float birth = hash(id * 1.7 + seed + 3.1) * 14.0;
	float grown = clamp((since * (0.25 + 1.5 * rain) - birth) * 0.8, 0.0, 1.0) * clamp(wetness * 1.5, 0.0, 1.0);
	vec2 c = (vec2(hash(id + 7.7 + seed), hash(id + 1.3 + seed)) - 0.5) * 0.5;
	// In the airflow fewer drops stay on, smaller, and their centre moves up so the tail fits in
	// the cell instead of being cut off at its edge.
	c.y += 0.2 * streak;
	float size = mix(0.12, 0.3, pow(hash(id + 9.1 + seed), 2.0)) * grown * (1.0 - 0.4 * streak);
	size *= step(hash(id + 4.4 + seed), 1.0 - 0.4 * streak);
	vec2 d = (f - c) / max(size, 1e-3);
	// Running drops are drawn out along the glass, with the thin end trailing.
	float tail = d.y < 0.0 ? 1.0 + 1.8 * streak : 1.0 + 0.3 * streak;
	d.y /= tail;
	d.x *= 1.0 + 0.35 * streak;
	float r2 = dot(d, d);
	float cover = (1.0 - smoothstep(0.75, 1.0, r2)) * step(1e-3, size);
	vec2 n = d * sqrt(max(1.0 - r2, 0.0));
	return vec3(n * cover, cover);
}

void fragment() {
	vec2 m = UV2;
	float since = min(since_wiped(m, pivot_a, radius_a), since_wiped(m, pivot_b, radius_b));
	since = min(since, 1e4);
	vec3 a = drops(m - vec2(0.0, flow_a), 0.022, since, 0.0, stretch);
	vec3 b = drops(m + vec2(0.0045, 0.0071 - flow_b), 0.011, since * 1.3, 11.0, stretch * 0.6);
	vec2 offset = (a.xy * 0.03 + b.xy * 0.016);
	float cover = clamp(a.z + b.z * 0.85, 0.0, 1.0);
	// Thin smeared film right behind a blade, fading within a second.
	float film = (1.0 - smoothstep(0.0, 1.1, since)) * step(since, 1e3) * 0.35 * wetness;
	vec3 seen = textureLod(screen, SCREEN_UV - offset, 1.5 * cover).rgb;
	// Drops invert the scene behind them: slightly brighter top, dark rim.
	float rim = smoothstep(0.55, 0.95, length(a.xy) + length(b.xy) * 0.7);
	seen = seen * mix(1.0, 0.7, rim) + vec3(0.05) * (1.0 - smoothstep(0.0, 0.6, length(a.xy + vec2(0.35, -0.35)))) * a.z;
	vec3 smear = textureLod(screen, SCREEN_UV, 2.5).rgb;
	ALBEDO = mix(smear, seen, step(0.001, cover));
	ALPHA = clamp(cover * 0.85 + film, 0.0, 1.0);
}
