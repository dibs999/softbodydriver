shader_type spatial;
// A walking person from one MultiMesh: the mesh's vertex colour tells the part (r: 0 body, 1-2
// left/right leg, 3-4 left/right arm) and the material (g: skin, top, trousers, shoes, hair). The
// legs and arms swing about the hip and shoulder in the vertex shader, so a whole crowd costs one
// draw call and one transform per person.
//   INSTANCE_CUSTOM: x walk phase (0..1 per stride pair), y swing amplitude (0 standing),
//                    z clothing (picks the top's colour and the trousers), w skin tone
// (No MultiMesh colours: they would be multiplied into the vertex colours that carry the parts.)
render_mode cull_back;

const float HIP_Y = 0.93;
const float SHOULDER_Y = 1.41;

varying vec3 top_colour;
varying float material_id;
varying float trouser_shade;
varying float skin_tone;

mat3 rot_x(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

void vertex() {
	float part = floor(COLOR.r * 8.0 + 0.5);
	material_id = floor(COLOR.g * 8.0 + 0.5);
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	float amp = INSTANCE_CUSTOM.y;
	float clothing = INSTANCE_CUSTOM.z;
	trouser_shade = fract(clothing * 13.7);
	skin_tone = INSTANCE_CUSTOM.w;
	// Tops: muted everyday colours, a few bright ones.
	vec3 palette[8] = vec3[](vec3(0.12, 0.13, 0.16), vec3(0.55, 0.56, 0.58), vec3(0.20, 0.27, 0.42), vec3(0.62, 0.12, 0.10),
		vec3(0.85, 0.83, 0.78), vec3(0.24, 0.36, 0.22), vec3(0.75, 0.55, 0.20), vec3(0.42, 0.25, 0.40));
	top_colour = palette[int(clothing * 7.999)];
	float swing = 0.0;
	float pivot = HIP_Y;
	if (part > 0.5 && part < 2.5) {
		swing = amp * 0.55 * sin(phase) * (part < 1.5 ? 1.0 : -1.0);
		pivot = HIP_Y;
	} else if (part > 2.5) {
		swing = amp * 0.45 * sin(phase) * (part < 3.5 ? -1.0 : 1.0);
		pivot = SHOULDER_Y;
	}
	if (part > 0.5) {
		vec3 p = VERTEX - vec3(0.0, pivot, 0.0);
		VERTEX = rot_x(swing) * p + vec3(0.0, pivot, 0.0);
		NORMAL = rot_x(swing) * NORMAL;
	}
	// Bob a little with each step.
	VERTEX.y += amp * 0.025 * abs(sin(phase));
}

void fragment() {
	vec3 skin = mix(vec3(0.93, 0.76, 0.64), vec3(0.36, 0.24, 0.17), skin_tone);
	// Jeans, black, grey, navy, beige, brown.
	vec3 legwear[6] = vec3[](vec3(0.13, 0.19, 0.33), vec3(0.035, 0.035, 0.04), vec3(0.26, 0.26, 0.27),
		vec3(0.06, 0.08, 0.14), vec3(0.45, 0.39, 0.30), vec3(0.22, 0.15, 0.10));
	vec3 trousers = legwear[int(trouser_shade * 5.999)];
	vec3 col = skin;
	float rough = 0.7;
	if (material_id > 0.5 && material_id < 1.5) { col = top_colour; rough = 0.85; }
	else if (material_id > 1.5 && material_id < 2.5) { col = trousers; rough = 0.9; }
	else if (material_id > 2.5 && material_id < 3.5) { col = vec3(0.06, 0.055, 0.05); rough = 0.5; }
	else if (material_id > 3.5) { col = mix(vec3(0.08, 0.06, 0.05), vec3(0.45, 0.33, 0.2), fract(skin_tone * 7.3)); rough = 0.8; }
	ALBEDO = col;
	ROUGHNESS = rough;
}
