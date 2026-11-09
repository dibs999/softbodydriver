shader_type spatial;
// Building facades on unit boxes scaled per building. Window bays are laid out per facade from
// the instance transform (symmetric margins, parapet, plinth). Windows are recessed with a
// parallax reveal and show fake rooms through interior mapping; the glass itself reflects the
// sky through the regular specular path.

uniform vec4 wall_color : source_color = vec4(0.55, 0.53, 0.5, 1.0);
uniform vec4 frame_color : source_color = vec4(0.85, 0.85, 0.82, 1.0);
uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;
uniform int style = 0;              // 0 plaster/stone, 1 brick, 2 glass office
uniform float floor_height = 3.3;
uniform float bay_width = 3.0;
uniform float window_width = 0.52;  // share of a bay
uniform float window_height = 0.56; // share of a storey
uniform float recess = 0.2;
global uniform float city_night;
global uniform float facade_detail;   // 0 = flat tinted glass, 1 = rooms behind the glass
uniform int debug = 0;

varying vec3 world_pos;
varying vec3 world_normal;
varying flat vec3 box_origin;
varying flat vec3 box_size;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float box_cov(vec2 d, vec2 half_size, vec2 fw) {
	vec2 c = clamp((half_size - d) / fw + 0.5, 0.0, 1.0);
	return c.x * c.y;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	box_origin = MODEL_MATRIX[3].xyz;
	box_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 base = wall_color.rgb;
	vec2 g_uv = vec2(world_pos.x + world_pos.z, world_pos.y) * 0.45;
	vec3 grain_col = texture(grain, g_uv).rgb;
	float grain_lum = dot(grain_col, vec3(0.333));
	base *= mix(0.86, 1.14, grain_lum / 0.45 * 0.5);
	float b_rand = hash(box_origin.xz * 0.071);
	base *= mix(0.9, 1.08, b_rand);
	ROUGHNESS = 0.85;
	SPECULAR = 0.35;
	ALBEDO = base;
	if (abs(n.y) < 0.5) {
		vec3 t = normalize(vec3(n.z, 0.0, -n.x));
		float width = abs(t.x) * box_size.x + abs(t.z) * box_size.z;
		float u = dot(world_pos - box_origin, t) + width * 0.5;
		float y = world_pos.y - (box_origin.y - box_size.y * 0.5);
		float fh = floor_height * mix(0.95, 1.08, fract(b_rand * 13.7));
		float usable = max(width - 1.6, bay_width);
		float bays = max(1.0, floor(usable / bay_width));
		float bay = usable / bays;
		float uu = u - 0.8;
		float bay_i = floor(uu / bay);
		float floor_i = floor(y / fh);
		float floors = floor((box_size.y - 1.1) / fh);
		vec2 cell = vec2(fract(uu / bay), fract(y / fh));
		bool in_grid = uu > 0.0 && uu < usable && floor_i < floors;
		float ww = window_width;
		float wh = window_height;
		float sill = 0.3;
		if (style == 2) { ww = 0.94; wh = 0.78; sill = 0.12; }
		// Wall detailing: brick courses, floor bands and a darker plinth.
		if (style == 1) {
			vec2 brick = vec2(u / 0.24, y / 0.075);
			brick.x += 0.5 * mod(floor(brick.y), 2.0);
			vec2 bf = fract(brick);
			float mortar = step(bf.x, 0.06) + step(bf.y, 0.12);
			base *= mix(mix(0.85, 1.15, hash(floor(brick))), 1.35, clamp(mortar, 0.0, 1.0));
		} else if (style == 0) {
			float band = step(abs(fract(y / fh) - 0.02), 0.02) * step(1.0, floor_i);
			base = mix(base, base * 1.12, band);
		} else {
			// Curtain wall: dark spandrel panels with aluminium mullions.
			base = mix(vec3(0.07, 0.08, 0.09), base * 0.4, 0.3);
		}
		base *= mix(0.72, 1.0, step(0.75, y));
		float parapet = step(box_size.y - 0.5, y);
		base = mix(base, base * 0.82, parapet);
		// Everything below is evaluated for every fragment (no derivatives in divergent branches)
		// and blended with anti-aliased coverage masks.
		float g = in_grid ? 1.0 : 0.0;
		vec2 pc = vec2(uu, y);
		vec2 fw = max(fwidth(pc), vec2(1e-4));
		vec2 local = vec2((cell.x - 0.5) * bay, cell.y * fh);              // metres in the cell
		vec2 half_w = vec2(ww * bay, wh * fh) * 0.5;
		vec2 center = vec2(0.0, (sill + wh * 0.5) * fh);
		vec2 d = abs(local - center);
		float outer = box_cov(d, half_w + 0.07, fw) * g;
		float open = box_cov(d, half_w, fw) * g;
		float sill_m = style == 2 ? 0.0 : box_cov(abs(local - vec2(0.0, center.y - half_w.y - 0.1)), vec2(half_w.x + 0.15, 0.06), fw) * (1.0 - outer) * g;
		vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 vt = vec3(dot(view, t), view.y, max(dot(view, n), 0.05));
		// Point on the recessed glass plane seen through this fragment.
		vec2 offset = vt.xy / vt.z * recess;
		vec2 glass = local - offset;
		vec2 gfw = max(fwidth(pc - offset), vec2(1e-4));
		float glass_m = box_cov(abs(glass - center), half_w, gfw);
		// Interior mapping into a room of the bay's size and 4 m depth.
		float room_rand = hash(vec2(bay_i, floor_i) + box_origin.xz * 0.013 + n.xz * 7.0);
		vec3 room_min = vec3(-bay * 0.5, 0.0, -4.0);
		vec3 room_max = vec3(bay * 0.5, fh, 0.0);
		// Keep the ray inside the room and its direction non-zero: masked-out fragments must not
		// produce NaNs, which a zero coverage weight would not cancel.
		vec3 o = vec3(clamp(glass, room_min.xy + 0.01, room_max.xy - 0.01), 0.0);
		vec3 dir = -vt;
		dir = vec3(dir.x == 0.0 ? 1e-4 : dir.x, dir.y == 0.0 ? 1e-4 : dir.y, dir.z);
		vec3 interior;
		float lit = step(0.62, room_rand);
		vec3 wall_in = mix(vec3(0.75, 0.72, 0.65), vec3(0.62, 0.66, 0.7), fract(room_rand * 5.3));
		vec3 p = vec3(0.0, 0.0, -2.0);
		if (facade_detail > 0.5) {
			vec3 tx = (mix(room_min, room_max, step(0.0, dir)) - o) / dir;
			float hit = min(min(tx.x, tx.y), tx.z);
			p = o + dir * hit;
			if (hit == tx.z) {
				interior = wall_in * 0.9 * mix(0.45, 1.0, step(0.9, p.y));   // furniture along the back wall
			} else if (hit == tx.y) {
				interior = dir.y < 0.0 ? vec3(0.32, 0.26, 0.2) * mix(0.7, 1.1, room_rand) : vec3(0.85, 0.85, 0.82);
			} else {
				interior = wall_in * 0.75;
			}
		} else {
			interior = wall_in * 0.6;   // flat room colour, no ray
		}
		interior *= 1.0 - clamp(-p.z / 8.0, 0.0, 0.4);   // deeper is darker
		// Blinds lowered to different heights.
		float blind = fract(room_rand * 17.3) * 0.7;
		float glass_v = (glass.y - (center.y - half_w.y)) / (half_w.y * 2.0);
		float blinds_m = clamp((glass_v - (1.0 - blind)) / (gfw.y / (half_w.y * 2.0)) + 0.5, 0.0, 1.0) * step(0.08, blind);
		vec3 blind_col = mix(vec3(0.78, 0.76, 0.7), vec3(0.45, 0.47, 0.5), step(0.5, fract(room_rand * 3.1)));
		interior = mix(interior, blind_col, blinds_m);
		float light = mix(0.035 + 0.13 * lit, 0.02 + 1.8 * lit, city_night) * (style == 2 ? 0.45 : 1.0);
		float fresnel = 0.04 + 0.96 * pow(1.0 - vt.z, 5.0);
		float mullion = style == 2 ? 0.0 : clamp((0.03 - abs(glass.x - center.x)) / gfw.x + 0.5, 0.0, 1.0) * (1.0 - blinds_m);
		vec3 frame_col = frame_color.rgb * (style == 2 ? 0.6 : 1.0);
		vec3 glass_albedo = mix(interior * 0.12 * (1.0 - fresnel), frame_col * 0.8, mullion);
		vec3 reveal_col = wall_color.rgb * 0.55;
		vec3 inner = mix(reveal_col, glass_albedo, glass_m);
		vec3 albedo = mix(base, base * 1.25, sill_m);
		albedo = mix(albedo, frame_col, outer - open);
		ALBEDO = mix(albedo, inner, open);
		EMISSION = interior * light * (1.0 - fresnel) * mix(vec3(1.0), vec3(1.0, 0.82, 0.6), lit) * open * glass_m * (1.0 - mullion);
		float inner_rough = mix(0.8, mix(0.04, 0.5, mullion), glass_m);
		ROUGHNESS = mix(mix(0.85, 0.5, outer - open), inner_rough, open);
		SPECULAR = mix(0.35, 0.5, open * glass_m);
		if (style == 2) {
			// Coated office glass: tinted mirror over a dim interior.
			float coat = open * glass_m * (1.0 - mullion);
			ALBEDO = mix(ALBEDO, vec3(0.30, 0.36, 0.40), coat);
			METALLIC = 0.85 * coat;
		}
		if (debug == 1) { ALBEDO = vec3(outer - open, open, glass_m); EMISSION = vec3(0.0); }
		if (debug == 2) { ALBEDO = vec3(sill_m, blinds_m, mullion); EMISSION = vec3(0.0); }
		if (debug == 3) { ALBEDO = vec3(fw * 20.0, 0.0); EMISSION = vec3(0.0); }
		if (open * (1.0 - glass_m) > 0.5) {
			// Reveal: the side of the opening, lit by its own orientation.
			vec2 gd = abs(glass - center) - half_w;
			vec3 rn = gd.x > gd.y ? t * -sign(glass.x - center.x) : vec3(0.0, -sign(glass.y - center.y), 0.0);
			NORMAL = normalize((VIEW_MATRIX * vec4(rn, 0.0)).xyz);
		}
	}
}
