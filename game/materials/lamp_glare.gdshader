shader_type spatial;
// The glare of a lit lamp seen from in front of it: a hot core, a soft halo and a faint horizontal
// streak, as the eye and a camera lens see headlights at night. Drawn additively on a camera-facing
// quad, strongest when looking down the lamp's axis and fading off to the side; by day only a hint.
// The quad's local +X is the car's forward axis: `facing_sign` -1 makes it a tail lamp.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.82);
uniform float facing_sign = 1.0;
uniform float strength = 0.0;       // 0 = lamp off
uniform float size = 0.32;          // quad half-size in metres at close range
uniform float narrow = 0.55;        // how quickly the glare fades off the lamp axis
global uniform float city_night;

varying float glare;

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 axis = normalize(MODEL_MATRIX[0].xyz) * facing_sign;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - centre;
	float dist = max(length(to_cam), 0.01);
	float facing = dot(to_cam / dist, axis);
	glare = strength * smoothstep(-0.05, narrow, facing) * mix(0.04, 1.0, city_night);
	// A distant lamp keeps a visible point: the quad grows with distance (eye and lens blur).
	float s = size * (1.0 + dist * 0.025);
	vec4 v = VIEW_MATRIX * vec4(centre, 1.0);
	v.xyz += normalize(-v.xyz) * min(0.35, dist * 0.5);   // in front of the lens housing
	v.xy += VERTEX.xy * 2.0 * s;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	float core = exp(-r2 * 30.0);
	float halo = exp(-sqrt(r2) * 5.0) * 0.35;
	float streak = exp(-abs(q.y) * 45.0) * exp(-abs(q.x) * 3.0) * 0.3;
	float k = glare * (core * 2.5 + halo + streak) * (1.0 - smoothstep(0.85, 1.0, sqrt(r2)));
	ALBEDO = tint * k;
	ALPHA = 1.0;
}
