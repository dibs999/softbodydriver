shader_type spatial;
// Window glass of the countryside houses. A share of the windows (their own MultiMesh) is lit from
// inside after dusk: warm lamp light faded in with the global city_night set by the weather.
global uniform float city_night;
uniform vec4 glass : source_color = vec4(0.10, 0.14, 0.17, 1.0);
uniform vec4 lamp : source_color = vec4(1.0, 0.70, 0.40, 1.0);
uniform float strength = 1.7;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	// Slightly different lamp warmth and brightness per window.
	float h = fract(sin(dot(floor(world_pos.xz * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = glass.rgb;
	ROUGHNESS = 0.08;
	METALLIC = 0.4;
	EMISSION = lamp.rgb * mix(vec3(1.0), vec3(1.05, 0.95, 0.85), h) * strength * (0.6 + 0.4 * h) * city_night;
}
