shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Weather visibility volumes: precipitation remains visible outside a shelter.
uniform int shelter_count = 0;
uniform vec3 shelter_centers[16];
uniform vec3 shelter_extents[16];
uniform bool cabin_enabled = false;
uniform mat4 cabin_inverse = mat4(1.0);
// Front windshield base/top, rear window top/base; positive X points forwards.
uniform vec4 cabin_profile;
// Half width, floor, front sill height, roof height, relative to axle-frame origin.
uniform vec4 cabin_dimensions;
uniform float cabin_rear_height;
uniform float cabin_roof_width;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	for (int i = 0; i < shelter_count; i++) {
		if (all(lessThan(abs(world_point - shelter_centers[i]), shelter_extents[i]))) discard;
	}
	if (cabin_enabled) {
		vec3 p = (cabin_inverse * vec4(world_point, 1.0)).xyz;
		if (p.x < cabin_profile.x && p.x > cabin_profile.w && p.y > cabin_dimensions.y) {
			float height = cabin_dimensions.w;
			float width = cabin_roof_width;
			if (p.x > cabin_profile.y) {
				float t = clamp((cabin_profile.x - p.x) / max(0.01, cabin_profile.x - cabin_profile.y), 0.0, 1.0);
				height = mix(cabin_dimensions.z, cabin_dimensions.w, 1.0 - pow(1.0 - t, 1.35));
				width = mix(cabin_dimensions.x, cabin_roof_width, pow(t, 0.7));
			} else if (p.x < cabin_profile.z) {
				float t = clamp((cabin_profile.z - p.x) / max(0.01, cabin_profile.z - cabin_profile.w), 0.0, 1.0);
				height = mix(cabin_dimensions.w, cabin_rear_height, pow(t, 1.25));
				width = mix(cabin_roof_width, cabin_dimensions.x, pow(t, 1.2));
			}
			if (p.y < height && abs(p.z) < width) discard;
		}
	}
	ALBEDO = vec3(0.70, 0.80, 0.90);
	ALPHA = 0.35;
}
