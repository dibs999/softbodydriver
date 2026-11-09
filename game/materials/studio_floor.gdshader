shader_type spatial;
// Menu studio floor: lit near the car, fading into the flat backdrop colour with distance so that
// no horizon edge is visible.
uniform vec4 floor_color : source_color = vec4(0.165, 0.176, 0.192, 1.0);
uniform vec4 backdrop : source_color = vec4(0.078, 0.086, 0.098, 1.0);
uniform float inner = 4.0;
uniform float outer = 16.0;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fade = smoothstep(inner, outer, length(world_pos.xz));
	ALBEDO = floor_color.rgb * (1.0 - fade);
	EMISSION = backdrop.rgb * fade;
	ROUGHNESS = 0.5;
	SPECULAR = 0.5 * (1.0 - fade);
}
