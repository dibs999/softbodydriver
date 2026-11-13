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
	p = mod(p, 512.0);   // world coordinates of a few km would leave the fract below without precision
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
		float fh = floor_height;   // one grid per material: the balconies (city.gd) line up with it
		float usable = max(width - 1.6, bay_width);
		float bays = max(1.0, floor(usable / bay_width));
		float bay = usable / bays;
		float uu = u - 0.8;
		float bay_i = floor(uu / bay);
		// Town buildings over 12 m have a shop ground floor (4.3 m storey with shop windows, some
		// glass doors and a fascia per shop unit of two bays); the upper storeys start above it.
		// Low town houses (8.8-12 m: room for a storey above the shop) have a corner shop in about four of ten, picked by position;
		// they keep their stone plinth, so the windows start above it and the door is round the side.
		bool low_shop = box_size.y > 8.8 && box_size.y <= 12.0 && hash(box_origin.xz * 0.037 + 0.5) < 0.4;
		bool shops = box_size.y > 12.0 || low_shop;
		float ground_h = shops ? 4.3 : 0.0;
		float yg = shops ? y - ground_h + fh : y;
		float floor_i = floor(yg / fh);
		float floors = floor((box_size.y - 1.1 - ground_h) / fh) + (shops ? 1.0 : 0.0);
		vec2 cell = vec2(fract(uu / bay), fract(yg / fh));
		bool in_grid = uu > 0.0 && uu < usable && floor_i < floors && (!shops || floor_i >= 1.0);
		float ww = window_width;
		float wh = window_height;
		float sill = 0.3;
		if (style == 2) { ww = 0.94; wh = 0.78; sill = 0.12; }
		float cell_h = fh;
		bool shop_zone = shops && y < ground_h;
		float shop_rand = hash(vec2(floor(bay_i / 2.0), 5.7) + box_origin.xz * 0.031 + n.xz * 3.0);
		bool door = shop_zone && !low_shop && hash(vec2(bay_i, 1.3) + box_origin.xz * 0.017 + n.xz) < 0.3;
		if (shop_zone) {
			cell = vec2(fract(uu / bay), y / ground_h);
			cell_h = ground_h;
			floor_i = -1.0;
			in_grid = uu > 0.0 && uu < usable;
			ww = 0.86;
			float bottom = door ? 0.04 : (low_shop ? 1.0 : 0.6);
			wh = (3.2 - bottom) / ground_h;
			sill = bottom / ground_h;
		}
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
		// Shop fascia: a sign band in the shop's colour across its two bays.
		vec3 fascia_col = vec3(0.0);
		float sign_glow = 0.0;
		{
			float k = fract(shop_rand * 9.1);
			fascia_col = k < 0.2 ? vec3(0.12, 0.2, 0.32) : (k < 0.4 ? vec3(0.42, 0.1, 0.09) : (k < 0.55 ? vec3(0.1, 0.26, 0.17)
				: (k < 0.7 ? vec3(0.78, 0.74, 0.66) : (k < 0.85 ? vec3(0.1, 0.1, 0.11) : vec3(0.62, 0.46, 0.14)))));
		}
		float fascia = shops && y > 3.4 && y < 4.05 && uu > 0.0 && uu < usable ? 1.0 : 0.0;
		base = mix(base, fascia_col, fascia);
		// Lettering: a centred row of glyph blocks in a contrasting tone on each shop's sign.
		{
			float unit_w = bay * 2.0;
			float su = fract(uu / unit_w) * unit_w - unit_w * 0.5;      // metres from the sign centre
			float sv = y - 3.725;
			float text_w = unit_w * mix(0.35, 0.7, fract(shop_rand * 4.3));
			float gi = floor(su / 0.24);
			float gx = fract(su / 0.24);
			float glyph = step(abs(su), text_w * 0.5) * step(abs(sv), 0.16) * step(0.12, gx) * step(gx, 0.86)
				* step(0.18, hash(vec2(gi, floor(shop_rand * 50.0))));
			// Glyph shapes: knock out a random notch so the blocks read as letters, not bars.
			float notch = step(0.5, hash(vec2(gi, 2.0 + floor(shop_rand * 50.0)))) * step(abs(gx - 0.5), 0.14) * step(abs(sv - 0.05), 0.06);
			glyph *= 1.0 - notch;
			vec3 ink = dot(fascia_col, vec3(0.333)) > 0.45 ? vec3(0.1, 0.1, 0.12) : vec3(0.93, 0.92, 0.88);
			base = mix(base, ink, glyph * fascia);
			sign_glow = glyph * fascia * step(0.5, dot(ink, vec3(0.333))) * step(0.3, fract(shop_rand * 6.1));
		}
		float parapet = step(box_size.y - 0.5, y);
		base = mix(base, base * 0.82, parapet);
		// Everything below is evaluated for every fragment (no derivatives in divergent branches)
		// and blended with anti-aliased coverage masks.
		float g = in_grid ? 1.0 : 0.0;
		vec2 pc = vec2(uu, y);
		vec2 fw = max(fwidth(pc), vec2(1e-4));
		vec2 local = vec2((cell.x - 0.5) * bay, cell.y * cell_h);          // metres in the cell
		vec2 half_w = vec2(ww * bay, wh * cell_h) * 0.5;
		vec2 center = vec2(0.0, (sill + wh * 0.5) * cell_h);
		vec2 d = abs(local - center);
		float outer = box_cov(d, half_w + 0.07, fw) * g;
		float open = box_cov(d, half_w, fw) * g;
		float sill_m = (style == 2 || shop_zone) ? 0.0 : box_cov(abs(local - vec2(0.0, center.y - half_w.y - 0.1)), vec2(half_w.x + 0.15, 0.06), fw) * (1.0 - outer) * g;
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
		vec3 room_max = vec3(bay * 0.5, cell_h, 0.0);
		// Keep the ray inside the room and its direction non-zero: masked-out fragments must not
		// produce NaNs, which a zero coverage weight would not cancel.
		vec3 o = vec3(clamp(glass, room_min.xy + 0.01, room_max.xy - 0.01), 0.0);
		vec3 dir = -vt;
		dir = vec3(dir.x == 0.0 ? 1e-4 : dir.x, dir.y == 0.0 ? 1e-4 : dir.y, dir.z);
		vec3 interior;
		// About a quarter of the rooms lit at night, each with its own lamp: brightness varies and
		// most are warm bulbs, some neutral, a few cool (LED, a television).
		float lit = shop_zone ? step(0.2, room_rand) : step(0.72, room_rand);
		float lamp = mix(0.45, 1.4, fract(room_rand * 7.7));
		float tone = fract(room_rand * 11.3);
		vec3 tint = tone < 0.6 ? vec3(1.0, 0.76, 0.5) : (tone < 0.88 ? vec3(1.0, 0.9, 0.78) : vec3(0.72, 0.82, 1.0));
		vec3 wall_in = mix(vec3(0.75, 0.72, 0.65), vec3(0.62, 0.66, 0.7), fract(room_rand * 5.3));
		vec3 p = vec3(0.0, 0.0, -2.0);
		if (facade_detail > 0.5) {
			vec3 tx = (mix(room_min, room_max, step(0.0, dir)) - o) / dir;
			float hit = min(min(tx.x, tx.y), tx.z);
			p = o + dir * hit;
			if (hit == tx.z || (shop_zone && hit == tx.x)) {
				interior = hit == tx.z ? wall_in * 0.9 * mix(0.45, 1.0, step(0.9, p.y)) : wall_in * 0.75;   // furniture along the back wall
				if (shop_zone) {
					// Shelves along the back and side walls (side walls index the goods by depth).
					float wall_u = hit == tx.z ? p.x : p.z;
					// Shelves of goods: coloured rows between pale shelf boards.
					float row = floor(p.y / 0.38);
					float item = floor(wall_u * 7.0 + row * 0.37);
					vec3 goods = vec3(hash(vec2(row, item)), hash(vec2(item, row + 3.0)), hash(vec2(row + 7.0, item + 1.0)));
					goods = mix(goods, vec3(0.55), 0.45) * mix(0.75, 1.05, hash(vec2(item * 0.3, row)));
					// Items stand on the boards with a little air above them.
					float on_board = step(fract(p.y / 0.38), 0.78);
					vec3 shelf = mix(wall_in * 0.55, goods, on_board);
					shelf = mix(shelf, vec3(0.85, 0.84, 0.8), step(0.9, fract(p.y / 0.38)));
					float rack = step(0.15, p.y) * step(p.y, 2.4);
					interior = mix(hit == tx.z ? wall_in : wall_in * 0.8, shelf * (hit == tx.z ? 1.0 : 0.85), rack);
					// Not every shop is a grocer's: the unit's hash picks fashion, a cafe or an office.
					float kind = fract(shop_rand * 13.7);
					vec3 bright_wall = mix(vec3(0.86, 0.84, 0.8), vec3(0.78, 0.8, 0.82), fract(shop_rand * 3.9));
					if (kind < 0.3) {
						// Fashion: clothes on a rail, 0.9-1.7 m, in a few colours, pale walls.
						float hang = floor(wall_u * 11.0);
						vec3 cloth = mix(vec3(hash(vec2(hang, 2.0)), hash(vec2(hang, 5.0)), hash(vec2(hang, 9.0))), vec3(0.2), 0.35);
						float garment = step(0.9, p.y) * step(p.y, 1.7 - 0.25 * hash(vec2(hang, 4.0))) * step(0.15, fract(wall_u * 11.0));
						float rail = step(1.72, p.y) * step(p.y, 1.76);
						interior = mix(bright_wall * (hit == tx.z ? 1.0 : 0.85), cloth, garment);
						interior = mix(interior, vec3(0.6), rail);
					} else if (kind < 0.52) {
						// Cafe / bakery: a wooden counter, a warm display on it, a menu board above.
						float counter = step(p.y, 1.0) * step(0.05, p.y);
						vec3 wood = vec3(0.32, 0.2, 0.12) * mix(0.8, 1.1, hash(vec2(floor(wall_u * 3.0), 1.0)));
						float display = step(1.0, p.y) * step(p.y, 1.3) * step(0.5, fract(wall_u * 4.0 + 0.2));
						float board = step(1.65, p.y) * step(p.y, 2.25) * step(abs(fract(wall_u * 0.35) - 0.5), 0.32);
						float lines = board * step(0.55, fract(p.y * 9.0)) * step(0.3, fract(wall_u * 3.3));
						interior = mix(vec3(0.72, 0.62, 0.5) * (hit == tx.z ? 1.0 : 0.85), wood, counter);
						interior = mix(interior, vec3(0.85, 0.6, 0.32), display * 0.8);
						interior = mix(interior, vec3(0.08, 0.09, 0.08), board);
						interior = mix(interior, vec3(0.8, 0.8, 0.75), lines * 0.8);
					} else if (kind < 0.7) {
						// Office / agency: desks at 0.75 m, a few large posters on a pale wall.
						float desk = step(0.7, p.y) * step(p.y, 0.78) + step(p.y, 0.7) * step(0.6, fract(wall_u * 1.3)) * 0.6;
						float poster_id = floor(wall_u * 0.8);
						float poster = step(1.3, p.y) * step(p.y, 2.1) * step(abs(fract(wall_u * 0.8) - 0.5), 0.28);
						vec3 poster_col = vec3(hash(vec2(poster_id, 11.0)), hash(vec2(poster_id, 12.0)), hash(vec2(poster_id, 13.0))) * 0.8 + 0.1;
						interior = mix(bright_wall * (hit == tx.z ? 1.0 : 0.85), vec3(0.35, 0.33, 0.3), clamp(desk, 0.0, 1.0));
						interior = mix(interior, poster_col, poster);
					}
				}
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
		float blind = shop_zone ? 0.0 : fract(room_rand * 17.3) * 0.7;
		float glass_v = (glass.y - (center.y - half_w.y)) / (half_w.y * 2.0);
		float blinds_m = clamp((glass_v - (1.0 - blind)) / (gfw.y / (half_w.y * 2.0)) + 0.5, 0.0, 1.0) * step(0.08, blind);
		vec3 blind_col = mix(vec3(0.78, 0.76, 0.7), vec3(0.45, 0.47, 0.5), step(0.5, fract(room_rand * 3.1)));
		interior = mix(interior, blind_col, blinds_m);
		float light = mix(0.035 + 0.13 * lit, 0.02 + 1.25 * lamp * lit, city_night) * (style == 2 ? 0.45 : 1.0);
		if (shop_zone) light = mix(0.22, 1.1, city_night) * lit;   // shops are lit inside by day, too
		light *= mix(1.0, 0.4, blinds_m * lit);   // a lowered blind only glows
		float fresnel = 0.04 + 0.96 * pow(1.0 - vt.z, 5.0);
		float mullion = style == 2 ? 0.0 : clamp((0.03 - abs(glass.x - center.x)) / gfw.x + 0.5, 0.0, 1.0) * (1.0 - blinds_m);
		if (style == 2) {
			// Curtain wall: an aluminium mullion between the two panes of each bay.
			mullion = clamp((0.025 - abs(glass.x - center.x)) / gfw.x + 0.5, 0.0, 1.0);
		}
		vec3 frame_col = frame_color.rgb * (style == 2 ? 0.6 : 1.0);
		vec3 glass_albedo = mix(interior * 0.12 * (1.0 - fresnel), frame_col * 0.8, mullion);
		vec3 reveal_col = wall_color.rgb * 0.55;
		vec3 inner = mix(reveal_col, glass_albedo, glass_m);
		vec3 albedo = mix(base, base * 1.25, sill_m);
		albedo = mix(albedo, frame_col, outer - open);
		ALBEDO = mix(albedo, inner, open);
		EMISSION = interior * light * (1.0 - fresnel) * mix(vec3(1.0), tint, lit) * open * glass_m * (1.0 - mullion);
		EMISSION += vec3(1.0, 0.97, 0.9) * sign_glow * city_night * 1.6;   // back-lit shop lettering
		float inner_rough = mix(0.8, mix(0.04, 0.5, mullion), glass_m);
		ROUGHNESS = mix(mix(0.85, 0.5, outer - open), inner_rough, open);
		SPECULAR = mix(0.35, 0.5, open * glass_m);
		if (style == 2) {
			// Coated office glass: tinted mirror over a dim interior.
			float coat = open * glass_m * (1.0 - mullion);
			// Each pane a touch different: tint, and a slight tilt (no pane sits perfectly flush), so
			// the reflected sky steps from pane to pane like on a real curtain wall.
			float pane = hash(vec2(floor((glass.x - center.x) / max(half_w.x, 0.01) + 2.0), room_rand * 91.0));
			ALBEDO = mix(ALBEDO, vec3(0.30, 0.36, 0.40) * mix(0.9, 1.1, pane), coat);
			METALLIC = 0.85 * coat;
			if (coat > 0.5) {
				vec3 tilt = n + t * (pane - 0.5) * 0.06 + vec3(0.0, 1.0, 0.0) * (fract(pane * 7.31) - 0.5) * 0.06;
				NORMAL = normalize((VIEW_MATRIX * vec4(normalize(tilt), 0.0)).xyz);
			}
			ALBEDO = mix(ALBEDO, frame_color.rgb * 0.55, mullion * open);
			METALLIC = mix(METALLIC, 0.6, mullion * open);
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
