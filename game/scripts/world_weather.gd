extends Node3D
## Local precipitation and coherent sky/light presets. Weather affects all wheel contacts.
const WeatherAudio := preload("res://scripts/weather_audio.gd")
const WEATHER_NAMES := ["Klar", "Bedeckt", "Regen", "Nebel"]
const RAIN := 2
const FOG := 3
## Per weather: cloud cover (sky, sun, ambient), daylight factor (the light sensor switches the
## dipped beams on in fog), road wetness it settles at, extra exponential fog density. Fog: ~150 m
## visibility (5 % contrast at 3 / density), the road damp from the mist.
const CLOUD := [0.0, 0.5, 1.0, 0.8]
const DAYLIGHT := [1.0, 0.75, 0.5, 0.42]
const WETNESS := [0.0, 0.0, 1.0, 0.3]
const FOG_EXTRA := [0.0, 0.0, 0.0, 0.02]
const CLOUD_COVER := [0.32, 0.82, 1.0, 0.9]
## How fast traffic drives in this weather (rain and fog: slower, longer gaps by the speed).
const TRAFFIC_SPEED := [1.0, 1.0, 0.88, 0.7]
const TIME_NAMES := ["Mittag", "Abend", "Nacht", "Morgen"]
const TIME_HOURS := [13.0, 18.5, 0.0, 7.0]
## 0 at night .. 1 in clear daylight (overcast halves it); read by the cabin fill light.
var daylight := 1.0
var weather_index := 0
var time_index := 0
var hour := 13.0
var automatic_time := false
var wetness := 0.0
var _environment: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D
var _surfaces: RefCounted
var _world: Node
var _sky: GameSky
var _rain: CPUParticles3D
var _day_top: Color
var _day_horizon: Color
var _day_energy := 1.25
var _day_fog := 0.00035
var _sky_fog := 0.12
var _rain_material: ShaderMaterial
var _shelters: Array = []
var _sheltered_vehicle: SBVehicle
var _cabin_inverse := Transform3D.IDENTITY
var _cabin_profile := Vector4.ZERO
var _cabin_dimensions := Vector4.ZERO
var _cabin_rear_height := 0.0
var _cabin_roof_width := 0.0
var _cabin_enabled := false
var _cabin_configured := false
var audio: Node

func configure(environment: Environment, sun: DirectionalLight3D, camera: Camera3D, surfaces: RefCounted = null, world: Node = null) -> void:
	_environment = environment
	_sun = sun
	_camera = camera
	_surfaces = surfaces
	_world = world
	_sky = environment.sky.sky_material as GameSky
	_day_top = _sky.sky_top_color
	_day_horizon = _sky.sky_horizon_color
	_day_energy = sun.light_energy
	_day_fog = environment.fog_density
	_sky_fog = environment.fog_sky_affect
	_build_rain()
	audio = WeatherAudio.new()
	add_child(audio)
	_apply_lighting()

func set_shelters(shelters: Array) -> void:
	_shelters.clear()
	var centers := PackedVector3Array()
	var extents := PackedVector3Array()
	for entry: Dictionary in shelters:
		if _shelters.size() >= 16: break
		var center: Vector3 = entry.get("center", Vector3.INF)
		var half: Vector3 = entry.get("half_extents", Vector3.ZERO)
		if not center.is_finite() or not half.is_finite() or half.x <= 0 or half.y <= 0 or half.z <= 0: continue
		_shelters.append({"center": center, "half_extents": half})
		centers.append(center)
		extents.append(half)
	centers.resize(16)
	extents.resize(16)
	_rain_material.set_shader_parameter("shelter_count", _shelters.size())
	_rain_material.set_shader_parameter("shelter_centers", centers)
	_rain_material.set_shader_parameter("shelter_extents", extents)

func set_vehicle_shelter(vehicle: SBVehicle, body: Dictionary) -> void:
	_sheltered_vehicle = vehicle
	_cabin_configured = is_instance_valid(vehicle) and not body.is_empty()
	_cabin_enabled = _cabin_configured
	_rain_material.set_shader_parameter("cabin_enabled", _cabin_enabled)
	if not _cabin_enabled: return
	# Continuous greenhouse profile matches the authored body; imported models
	# use their physical envelope. No drops are removed outside the cabin.
	var length := float(body.get("length", 4.26))
	var origin_x := length - float(body.get("frontOverhang", 0.89)) - float(body.get("wheelbase", 2.62)) * 0.5
	var origin_y := float(body.get("groundClearance", 0.14)) + 0.04
	var front := length - float(body.get("hoodLength", 1.15))
	var front_top := front - float(body.get("windshieldRun", 0.80))
	var rear_top := front_top - float(body.get("roofLength", 1.25))
	var rear := maxf(0.08, rear_top - float(body.get("rearWindowRun", 0.45)))
	_cabin_profile = Vector4(front, front_top, rear_top, rear) - Vector4.ONE * origin_x
	_cabin_dimensions = Vector4(float(body.get("width", 1.79)) * 0.5 - 0.115, -0.04,
		float(body.get("hoodHeight", 0.98)) - origin_y, float(body.get("height", 1.45)) - origin_y - 0.035)
	_cabin_rear_height = float(body.get("beltHeight", 1.0)) + 0.035 - origin_y
	_cabin_roof_width = float(body.get("width", 1.79)) * 0.5 * float(body.get("roofWidthRatio", 0.78))
	_rain_material.set_shader_parameter("cabin_profile", _cabin_profile)
	_rain_material.set_shader_parameter("cabin_dimensions", _cabin_dimensions)
	_rain_material.set_shader_parameter("cabin_rear_height", _cabin_rear_height)
	_rain_material.set_shader_parameter("cabin_roof_width", _cabin_roof_width)
	_update_cabin()

static func doors_seal_cabin(states: Array) -> bool:
	# Conservative whole-cabin proxy. Door openings are not individually ray-traced.
	# Vehicles without simulated doors retain their original intact envelope.
	for state: Dictionary in states:
		if bool(state.get("missing", false)) or not bool(state.get("attached", true)) or not bool(state.get("latched", true)) or absf(float(state.get("angle_degrees", 0))) > 3:
			return false
	return true

func _update_cabin() -> void:
	if not _cabin_configured: return
	if not is_instance_valid(_sheltered_vehicle):
		_cabin_enabled = false
		_cabin_configured = false
		_rain_material.set_shader_parameter("cabin_enabled", false)
		return
	_cabin_enabled = doors_seal_cabin(_sheltered_vehicle.call("get_door_states")) if _sheltered_vehicle.has_method("get_door_states") else true
	_rain_material.set_shader_parameter("cabin_enabled", _cabin_enabled)
	var basis := _sheltered_vehicle.get_visual_basis()
	_cabin_inverse = Transform3D(Basis(-basis.z, basis.y, basis.x), _sheltered_vehicle.get_position_ws()).affine_inverse()
	_rain_material.set_shader_parameter("cabin_inverse", _cabin_inverse)

func is_roof_sheltered(point: Vector3) -> bool:
	# Roof and cabin are separate so the mixer can distinguish tin-roof rain from a cabin.
	for entry: Dictionary in _shelters:
		var offset: Vector3 = (point - entry.center).abs()
		var half: Vector3 = entry.half_extents
		if offset.x < half.x and offset.y < half.y and offset.z < half.z: return true
	return false

func is_sheltered(point: Vector3) -> bool:
	return is_roof_sheltered(point) or is_cabin_sheltered(point)

func is_cabin_sheltered(point: Vector3) -> bool:
	if not _cabin_enabled: return false
	var p := _cabin_inverse * point
	if p.x >= _cabin_profile.x or p.x <= _cabin_profile.w or p.y <= _cabin_dimensions.y: return false
	var height := _cabin_dimensions.w
	var width := _cabin_roof_width
	if p.x > _cabin_profile.y:
		var t := clampf((_cabin_profile.x - p.x) / maxf(0.01, _cabin_profile.x - _cabin_profile.y), 0, 1)
		height = lerpf(_cabin_dimensions.z, height, 1.0 - pow(1.0 - t, 1.35))
		width = lerpf(_cabin_dimensions.x, width, pow(t, 0.7))
	elif p.x < _cabin_profile.z:
		var t := clampf((_cabin_profile.z - p.x) / maxf(0.01, _cabin_profile.z - _cabin_profile.w), 0, 1)
		height = lerpf(height, _cabin_rear_height, pow(t, 1.25))
		width = lerpf(width, _cabin_dimensions.x, pow(t, 1.2))
	return p.y < height and absf(p.z) < width

func cycle_weather() -> void:
	weather_index = (weather_index + 1) % WEATHER_NAMES.size()
	_apply_lighting()

func cycle_time() -> void:
	time_index = (time_index + 1) % TIME_HOURS.size()
	hour = TIME_HOURS[time_index]
	_apply_lighting()

## Short HUD form: clock and weather only (keys are listed in the F1 help).
func get_brief() -> String:
	return "%02d:%02d  ·  %s%s" % [int(hour), int(fmod(hour, 1.0) * 60), WEATHER_NAMES[weather_index], "" if automatic_time else "  ·  Zeit steht"]

func get_status() -> String:
	return "%02d:%02d · %s · F7 Wetter / F8 Tageszeit / Umschalt+F8 Zeitlauf %s" % [int(hour), int(fmod(hour, 1.0) * 60), WEATHER_NAMES[weather_index], "an" if automatic_time else "aus"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F7:
		cycle_weather()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F8:
		if event.shift_pressed:
			automatic_time = not automatic_time
		else:
			cycle_time()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _environment == null:
		return
	var paused := is_instance_valid(_world) and bool(_world.get("paused"))
	var scale := float(_world.get("time_scale")) if is_instance_valid(_world) else 1.0
	var step := 0.0 if paused else delta * scale
	if automatic_time:
		hour = fposmod(hour + step / 30.0, 24.0)
	var wet_target: float = WETNESS[weather_index]
	wetness = move_toward(wetness, wet_target, step / (20.0 if wet_target > wetness else 90.0))
	if _surfaces:
		_surfaces.set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("road_wetness", wetness)
	if is_instance_valid(_camera):
		_rain.global_position = _camera.global_position + Vector3(0, 9, 0)
	_update_cabin()
	_rain.speed_scale = 0.0 if paused else scale
	if audio and is_instance_valid(_camera):
		var game := get_node_or_null("/root/Game")
		var master := float(game.get("settings").get("master_volume", 0.8)) if game else 0.8
		audio.set_conditions(1.0 if weather_index == RAIN else 0.0, paused, scale,
			is_cabin_sheltered(_camera.global_position), is_roof_sheltered(_camera.global_position), master)
	if automatic_time and step > 0:
		_apply_lighting()

func _apply_lighting() -> void:
	if _environment == null:
		return
	var elevation := sin((hour - 6.0) * TAU / 24.0)
	var daylight := smoothstep(-0.12, 0.35, elevation)
	self.daylight = daylight * float(DAYLIGHT[weather_index])
	RenderingServer.global_shader_parameter_set("city_night", 1.0 - smoothstep(-0.05, 0.2, elevation))
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(elevation))) * daylight
	var cloud: float = CLOUD[weather_index]
	_sun.rotation_degrees.x = -maxf(8.0, elevation * 75.0) if elevation > 0 else -35.0
	_sun.rotation_degrees.y = (hour - 12.0) * 15.0 - 35.0
	_sun.light_energy = lerpf(0.045, _day_energy * (1.0 - cloud * 0.75), daylight)
	_sun.light_color = Color(0.42, 0.53, 0.8).lerp(Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.48, 0.22), dusk), daylight)
	_sky.sky_top_color = Color(0.008, 0.015, 0.04).lerp(_day_top.lerp(Color(0.22, 0.27, 0.33), cloud), daylight)
	_sky.sky_horizon_color = Color(0.025, 0.04, 0.075).lerp(_day_horizon.lerp(Color(0.44, 0.48, 0.52), cloud).lerp(Color(0.9, 0.40, 0.20), dusk * (1.0 - cloud)), daylight)
	_sky.ground_horizon_color = _sky.sky_horizon_color.darkened(0.25)
	_sky.ground_bottom_color = Color(0.03, 0.03, 0.04).lerp(Color(0.22, 0.21, 0.2), daylight)
	_sky.cloud_coverage = CLOUD_COVER[weather_index]
	_sky.cloud_light = Color(0.25, 0.27, 0.33).lerp(Color(1.0, 0.98, 0.95).lerp(Color(1.0, 0.72, 0.52), dusk), daylight)
	_sky.cloud_shadow = Color(0.06, 0.07, 0.1).lerp(Color(0.56, 0.61, 0.69).lerp(Color(0.42, 0.45, 0.5), cloud), daylight)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.35, 0.45, 0.65).lerp(Color(0.78, 0.84, 0.94), daylight)
	_environment.ambient_light_energy = lerpf(0.10, 0.72 - cloud * 0.16, daylight)
	_environment.fog_light_color = _sky.sky_horizon_color
	_environment.fog_density = _day_fog + cloud * 0.0012 + float(FOG_EXTRA[weather_index]) * lerpf(0.6, 1.0, daylight)
	_environment.fog_sky_affect = _sky_fog
	# Volumetric mist after dark on the higher presets (Leuchteffekte on, Forward+): car lights then
	# glow in the fog as real beams do. It takes over half of the plain fog density. By day the plain
	# fog alone looks right (the volume greyed the scene).
	var game_state := get_node_or_null("/root/Game")
	var volumetric := weather_index == FOG and daylight < 0.4 and game_state != null and bool(game_state.get("graphics").get("glow", false)) \
		and RenderingServer.get_current_rendering_method() == "forward_plus"
	_environment.volumetric_fog_enabled = volumetric
	if volumetric:
		_environment.fog_density -= float(FOG_EXTRA[weather_index]) * lerpf(0.6, 1.0, daylight) * 0.5
		_environment.volumetric_fog_density = 0.012
		_environment.volumetric_fog_albedo = Color(0.85, 0.86, 0.88)
		_environment.volumetric_fog_length = 80.0
		_environment.volumetric_fog_anisotropy = 0.6   # forward scattering: beams glow towards the eye
		_environment.volumetric_fog_ambient_inject = 0.15
	if weather_index == FOG:
		# Mist scatters the light: a flat pale grey sky and horizon, the sun only a glow. The
		# fog also covers the sky, or the clouds stay sharp above a white-washed tree line.
		_environment.fog_sky_affect = 0.95
		var mist := Color(0.62, 0.64, 0.66).lerp(Color(0.05, 0.055, 0.065), 1.0 - daylight)
		_sky.sky_top_color = _sky.sky_top_color.lerp(mist, 0.7)
		_sky.sky_horizon_color = mist
		_environment.fog_light_color = mist
		_sun.light_energy *= 0.55
	_rain.emitting = weather_index == RAIN

func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 700
	var game := get_node_or_null("/root/Game")
	if game and int(game.get("graphics").get("effects", 1)) == 0:
		_rain.amount = 280
	_rain.lifetime = 0.8
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(13, 2, 13)
	_rain.direction = Vector3(0.10, -1, 0.04)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 22
	_rain.initial_velocity_max = 28
	_rain.gravity = Vector3(0, -3, 0)
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.35, 0.012)
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = preload("res://shaders/rain.gdshader")
	streak.material = _rain_material
	_rain.mesh = streak
	add_child(_rain)
