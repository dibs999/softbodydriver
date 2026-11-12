shader_type sky;
// Daytime atmosphere, sun disk and a procedural cloud layer. Colours follow the weather/time of day
// (world_weather.gd drives the same parameters a ProceduralSkyMaterial would have).

uniform vec4 sky_top_color : source_color = vec4(0.18, 0.36, 0.74, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.64, 0.75, 0.88, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.52, 0.55, 0.58, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.20, 0.19, 0.18, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform vec4 cloud_light : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.55, 0.60, 0.68, 1.0);
uniform float cloud_scale = 0.00045;
uniform vec2 wind = vec2(6.0, 2.0);
uniform float sun_disk_size = 0.9995;
uniform float horizon_softness = 0.32;
uniform float energy = 1.0;

float hash(vec2 p) {
	p = mod(p, 512.0);   // world coordinates of a few km would leave the fract below without precision
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p = r * p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(1.0);
	float mu = dot(dir, sun_dir);

	// Sky gradient: deep zenith, bright hazy horizon (Rayleigh-like falloff).
	float t = pow(clamp(h, 0.0, 1.0), horizon_softness);
	vec3 col = mix(sky_horizon_color.rgb, sky_top_color.rgb, t);
	// Forward scattering glow around the sun (Mie) and a warm horizon band toward it.
	float mie = pow(max(mu, 0.0), 8.0) * 0.35 + pow(max(mu, 0.0), 64.0) * 0.6;
	col += sun_col * mie * 0.18 * (1.0 - cloud_coverage * 0.8);
	col = mix(col, col * vec3(1.06, 1.0, 0.94), exp(-max(h, 0.0) * 12.0) * max(mu, 0.0));

	if (h < 0.0) {
		float g = clamp(-h * 4.0, 0.0, 1.0);
		col = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, g);
	} else {
		// Sun disk (hidden behind thick clouds).
		float disk = smoothstep(sun_disk_size, sun_disk_size + 0.0002, mu);
		col += sun_col * disk * 12.0 * (1.0 - smoothstep(0.55, 0.9, cloud_coverage));

		// Cloud layer on a plane ~1.5 km up, faded out toward the horizon.
		if (cloud_coverage > 0.01 && !AT_CUBEMAP_PASS) {
			vec2 uv = dir.xz / max(h, 0.03) * 1500.0 * cloud_scale + TIME * wind * cloud_scale;
			float n = fbm(uv);
			float detail = fbm(uv * 3.1 + 4.0);
			float threshold = mix(0.78, 0.30, cloud_coverage);
			float density = smoothstep(threshold, threshold + 0.22, n * 0.78 + detail * 0.22);
			// Self-shadowing: sample toward the sun.
			float toward = fbm(uv + sun_dir.xz * 0.05);
			float lit = clamp(1.0 - (toward - n) * 3.0, 0.35, 1.25);
			vec3 cloud = mix(cloud_shadow.rgb, cloud_light.rgb * (0.65 + 0.35 * sun_col), clamp(lit * (1.0 - density * 0.45), 0.0, 1.0));
			cloud = mix(cloud, cloud_shadow.rgb * 0.75, smoothstep(0.65, 1.0, cloud_coverage) * density);
			cloud += sun_col * pow(max(mu, 0.0), 12.0) * 0.25 * (1.0 - density);
			float fade = smoothstep(0.0, 0.12, h);
			col = mix(col, cloud, density * fade);
			// Overcast: the whole dome greys toward the cloud base.
			col = mix(col, cloud_shadow.rgb, smoothstep(0.7, 1.0, cloud_coverage) * fade * 0.6);
		} else if (cloud_coverage > 0.01) {
			col = mix(col, cloud_shadow.rgb, cloud_coverage * 0.5 * smoothstep(0.0, 0.2, h));
		}
	}
	COLOR = col * energy;
}
