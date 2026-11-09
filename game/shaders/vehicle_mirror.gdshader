shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D reflection_texture : source_color, filter_linear, repeat_disable;
uniform mat4 mirror_projection;
uniform mat4 mirror_view;
uniform bool reflection_valid = false;
varying vec3 reflected_world_point;

void vertex() {
	reflected_world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 clip = mirror_projection * mirror_view * vec4(reflected_world_point, 1.0);
	vec2 uv = clip.xy / max(clip.w, 0.00001) * 0.5 + 0.5;
	uv.y = 1.0 - uv.y;
	if (reflection_valid && clip.w > 0.0 && all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		ALBEDO = texture(reflection_texture, uv).rgb * vec3(0.92, 0.95, 0.97);
	} else {
		ALBEDO = vec3(0.025, 0.035, 0.045);
	}
}
