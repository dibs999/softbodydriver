class_name GameSky
extends ShaderMaterial
## Sky with atmosphere, sun disk and procedural clouds. Exposes the same colour properties as
## ProceduralSkyMaterial so the weather and time-of-day code can drive either.

const SKY_SHADER := preload("res://shaders/sky.gdshader")

var sky_top_color: Color:
	set(v): set_shader_parameter("sky_top_color", v)
	get: return get_shader_parameter("sky_top_color")
var sky_horizon_color: Color:
	set(v): set_shader_parameter("sky_horizon_color", v)
	get: return get_shader_parameter("sky_horizon_color")
var ground_horizon_color: Color:
	set(v): set_shader_parameter("ground_horizon_color", v)
	get: return get_shader_parameter("ground_horizon_color")
var ground_bottom_color: Color:
	set(v): set_shader_parameter("ground_bottom_color", v)
	get: return get_shader_parameter("ground_bottom_color")
var cloud_coverage: float:
	set(v): set_shader_parameter("cloud_coverage", clampf(v, 0.0, 1.0))
	get: return float(get_shader_parameter("cloud_coverage"))
var cloud_light: Color:
	set(v): set_shader_parameter("cloud_light", v)
	get: return get_shader_parameter("cloud_light")
var cloud_shadow: Color:
	set(v): set_shader_parameter("cloud_shadow", v)
	get: return get_shader_parameter("cloud_shadow")

func _init() -> void:
	shader = SKY_SHADER
	sky_top_color = Color(0.18, 0.36, 0.74)
	sky_horizon_color = Color(0.64, 0.75, 0.88)
	ground_horizon_color = Color(0.52, 0.55, 0.58)
	ground_bottom_color = Color(0.20, 0.19, 0.18)
	cloud_coverage = 0.35
	cloud_light = Color(1.0, 0.98, 0.95)
	cloud_shadow = Color(0.55, 0.60, 0.68)
