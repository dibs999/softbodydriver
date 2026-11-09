shader_type spatial;
// Leaf and needle cards: alpha-scissored, two-sided with volumetric (crown-shaped) normals,
// light transmission, per-tree colour variation and gentle wind sway.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint_a : source_color = vec4(1.0);
uniform vec4 tint_b : source_color = vec4(0.85, 0.92, 0.7, 1.0);
uniform vec4 autumn : source_color = vec4(0.95, 0.75, 0.35, 1.0);
uniform float autumn_amount = 0.12;     // share of trees with yellowish foliage
uniform float alpha_cut = 0.42;
uniform float wind_strength = 1.0;
uniform float translucency = 0.55;

varying vec3 view_normal;
varying float tree_rand;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	tree_rand = hash(origin.xz * 0.137);
	// Sway grows with height above the base; each card adds a small flutter.
	float t = TIME * 1.1 + tree_rand * 6.283;
	float height = max(VERTEX.y, 0.0);
	vec2 sway = vec2(sin(t), cos(t * 0.83)) * 0.012 * height;
	float flutter = sin(TIME * 4.7 + COLOR.g * 40.0 + VERTEX.x * 2.0) * 0.035;
	VERTEX.xz += (sway + vec2(flutter, -flutter * 0.6)) * wind_strength;
	VERTEX.y += flutter * 0.5 * wind_strength;
	view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 tex = texture(leaf_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 tint = mix(tint_a.rgb, tint_b.rgb, COLOR.g);
	tint = mix(tint, tint * autumn.rgb * 1.25, step(1.0 - autumn_amount, tree_rand));
	tint *= mix(0.88, 1.12, fract(tree_rand * 7.31));
	vec3 col = tex.rgb * tint * mix(0.42, 1.0, COLOR.r);
	ALBEDO = col;
	// Ignore the per-side flip: the crown normal stays valid from both sides of a card.
	NORMAL = normalize(view_normal);
	ROUGHNESS = 0.78;
	SPECULAR = 0.32;
	BACKLIGHT = col * translucency;
}
