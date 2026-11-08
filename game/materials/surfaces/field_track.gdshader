shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;

uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float width = 6.4;
uniform float greenery = 0.7;

void fragment() {
	vec2 tile = UV * vec2(width / 1.8, 5.0);
	vec3 earth = texture(soil, tile).rgb * vec3(0.62, 0.46, 0.30);
	vec3 plants = texture(grass, tile * 0.72).rgb * vec3(0.73, 0.85, 0.57);
	float across = (UV.x - 0.5) * width;
	float rut = min(abs(across - 0.79), abs(across + 0.79));
	float worn = 1.0 - smoothstep(0.25, 0.60, rut);
	float center = (1.0 - smoothstep(0.2, 0.58, abs(across))) * greenery;
	float shoulder = smoothstep(width * 0.32, width * 0.5, abs(across));
	ALBEDO = mix(earth * mix(1.0, 0.78, worn), plants, max(center, shoulder * 0.85));
	NORMAL_MAP = texture(soil_normal, tile).rgb;
	NORMAL_MAP_DEPTH = 0.45;
	ROUGHNESS = 0.98;
	ALPHA = 1.0 - smoothstep(0.42, 0.5, abs(UV.x - 0.5));
}
