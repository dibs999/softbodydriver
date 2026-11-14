shader_type spatial;
// A textured surface cut out by its alpha: decals such as manhole covers, gully grates and
// painted arrows. Cut by hand: StandardMaterial3D's alpha scissor drew these black in the
// mobile renderer.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float cut = 0.5;

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < cut) {
		discard;
	}
	ALBEDO = t.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
