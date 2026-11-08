shader_type spatial;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 texture_repeats = vec2(4.5, 6.0);
uniform float road_width = 9.0;
uniform int lanes = 2;
uniform bool dirt = false;
uniform vec4 divider_color : source_color = vec4(0.86, 0.85, 0.77, 1.0);

void fragment() {
	vec2 surface_uv = UV * texture_repeats;
	vec3 base = texture(surface_color, surface_uv).rgb;
	NORMAL_MAP = texture(surface_normal, surface_uv).rgb;
	NORMAL_MAP_DEPTH = dirt ? 0.54 : 0.38;
	ROUGHNESS = dirt ? 0.98 : 0.85;
	if (dirt) {
		float rut_distance = min(abs(UV.x - 0.31), abs(UV.x - 0.69));
		float shoulder = smoothstep(0.34, 0.50, abs(UV.x - 0.5));
		base *= vec3(0.83, 0.68, 0.49);
		base *= mix(0.73, 1.0, smoothstep(0.018, 0.082, rut_distance)) * mix(1.0, 0.84, shoulder);
	} else {
		float u = UV.x;
		float pixel = max(fwidth(u) * 0.55, 0.0002);
		float edge_distance = abs(min(u, 1.0 - u) - 0.22 / road_width);
		float edge = 1.0 - smoothstep(0.06 / road_width - pixel, 0.06 / road_width + pixel, edge_distance);
		float lane_distance = abs(fract(u * float(lanes) + 0.5) - 0.5) / float(lanes);
		float divider = 1.0 - smoothstep(0.06 / road_width - pixel, 0.06 / road_width + pixel, lane_distance);
		float dash_distance = abs(fract(UV.y) - 0.5);
		float dash_pixel = max(fwidth(UV.y) * 0.6, 0.0002);
		divider *= (1.0 - smoothstep(0.24 - dash_pixel, 0.24 + dash_pixel, dash_distance)) * step(0.10, u) * step(u, 0.90);
		base = mix(base, divider_color.rgb, divider * 0.95);
		base = mix(base, vec3(0.84, 0.83, 0.78), edge * 0.95);
	}
	ALBEDO = base;
}
