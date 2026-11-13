extends Node3D
## Bounded particle pools: world-space smoke remains behind the moving vehicle.
## No physics objects, no per-frame image creation, reduced budget on Performance.

var vehicle: SBVehicle
var world: SBWorld
var dirt := false
var surfaces: RefCounted
var marks: MultiMeshInstance3D
var _electric := false
var _tread := ""   # the car's tyre tread pattern (get_info)
var wheel_surfaces := ["asphalt", "asphalt", "asphalt", "asphalt"]
var _surface_timer := 0.0
## 0 clean .. 1 caked; grows on loose ground, washes off in the rain.
var grime := 0.0
var grime_color := Color(0.36, 0.28, 0.19)
var _paint_materials: Array = []
var _grime_applied := -1.0
var _mark_timer := 0.0
var _effect_time := 0.0
var tires: Array[CPUParticles3D] = []
var sparks: Array[CPUParticles3D] = []
var body_sparks: CPUParticles3D   # bodywork or a rim grinding on the road
var engine_smoke: CPUParticles3D
var exhaust: CPUParticles3D
var flames: CPUParticles3D        # vehicle fire (engine bay or fuel tank)
var fire_light: OmniLight3D
var _previous_position := Vector3.INF
var _levels := PackedFloat32Array([0, 0, 0, 0])
static var _smoke_mesh: QuadMesh
static var _spark_mesh: SphereMesh
static var _streak_mesh: BoxMesh
static var _drop_mesh: QuadMesh
var splashes: Array[CPUParticles3D] = []   # water thrown up by each wheel (a ford, a puddle)


func _ready() -> void:
	if _smoke_mesh == null:
		_make_meshes()
	if vehicle:
		_electric = bool(vehicle.get_info().get("electric", false))
	for i in 4:
		tires.append(_emitter(48, 2.8, false))
		sparks.append(_emitter(10, 0.35, true))
	for i in 4:
		splashes.append(_splash_emitter())
	body_sparks = _emitter(96, 0.42, true)
	# Grinding steel throws white-hot streaks that cool to orange: thin rods stretched along their
	# flight path, added onto the scene (they are light, not matter).
	body_sparks.mesh = _streak_mesh
	body_sparks.particle_flag_align_y = true
	body_sparks.spread = 28.0
	body_sparks.flatness = 0.55
	body_sparks.gravity = Vector3(0, -9.8, 0)
	body_sparks.initial_velocity_min = 3.0
	body_sparks.initial_velocity_max = 9.0
	body_sparks.angular_velocity_min = 0.0
	body_sparks.angular_velocity_max = 0.0
	body_sparks.scale_amount_min = 0.6
	body_sparks.scale_amount_max = 1.4
	body_sparks.emission_sphere_radius = 0.05
	var hot := Gradient.new()
	hot.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	hot.colors = PackedColorArray([Color(1, 1, 0.9, 1), Color(1, 0.85, 0.5, 1), Color(1, 0.45, 0.1, 0.8), Color(0.7, 0.15, 0.02, 0)])
	body_sparks.color_ramp = hot
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1.0))
	shrink.add_point(Vector2(1, 0.45))
	body_sparks.scale_amount_curve = shrink
	engine_smoke = _emitter(64, 3.8, false)
	exhaust = _emitter(18, 0.8, false)
	flames = _emitter(90, 0.5, false)
	var fire_ramp := Gradient.new()
	fire_ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.45, 0.8, 1.0])
	fire_ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 0.0), Color(1.0, 0.62, 0.12, 1.0), Color(0.95, 0.30, 0.04, 0.9),
		Color(0.45, 0.08, 0.02, 0.5), Color(0.08, 0.06, 0.05, 0.0)])
	flames.color_ramp = fire_ramp
	flames.gravity = Vector3(0, 4.5, 0)
	flames.initial_velocity_min = 0.9
	flames.initial_velocity_max = 2.6
	flames.spread = 28.0
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(0.45, 0.05, 0.35)
	flames.scale_amount_min = 0.25
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.omni_range = 7.0
	fire_light.light_energy = 0.0
	fire_light.shadow_enabled = false
	add_child(fire_light)
	Game.graphics_preset_changed.connect(_quality)
	_quality()


static func _make_meshes() -> void:
	# Explicit particle tint/alpha avoids opaque black billboards observed with
	# StandardMaterial3D's particle billboard path on the compatibility renderer.
	# A continuous radial mask stays soft at any size without texture edge sampling.
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
void vertex() {
    mat4 facing = INV_VIEW_MATRIX;
    facing[0] *= length(MODEL_MATRIX[0].xyz);
    facing[1] *= length(MODEL_MATRIX[1].xyz);
    facing[2] *= length(MODEL_MATRIX[2].xyz);
    facing[3] = MODEL_MATRIX[3];
    MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float edge = pow(max(0.0, 1.0 - dot(p, p)), 2.5);
    float wisps = 0.82 + 0.12 * sin(p.x * 16.0 + sin(p.y * 11.0));
    ALBEDO = COLOR.rgb;
    ALPHA = clamp(COLOR.a, 0.0, 1.0) * edge * wisps * 0.65;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.material = mat
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	_spark_mesh = SphereMesh.new()
	_spark_mesh.radius = 0.025
	_spark_mesh.height = 0.05
	_spark_mesh.radial_segments = 4
	_spark_mesh.rings = 2
	_spark_mesh.material = spark_mat
	var streak_mat := StandardMaterial3D.new()
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.vertex_color_use_as_albedo = true
	streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	streak_mat.albedo_color = Color(2.2, 2.0, 1.6)   # over-bright so glow picks the streaks up
	# Water droplets: small bright billboards with a sharp edge and a highlight, stretched along
	# their flight by the emitter's alignment.
	var drop_shader := Shader.new()
	drop_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
void vertex() {
    mat4 facing = INV_VIEW_MATRIX;
    facing[0] *= length(MODEL_MATRIX[0].xyz);
    facing[1] *= length(MODEL_MATRIX[1].xyz);
    facing[2] *= length(MODEL_MATRIX[2].xyz);
    facing[3] = MODEL_MATRIX[3];
    MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    p.y *= 0.45;   // elongated drop
    float d = dot(p, p);
    float body = 1.0 - smoothstep(0.55, 0.85, d);
    float glint = 1.0 - smoothstep(0.0, 0.12, dot(p - vec2(-0.25, -0.1), p - vec2(-0.25, -0.1)));
    ALBEDO = mix(COLOR.rgb, vec3(1.0), glint * 0.7);
    ALPHA = clamp(COLOR.a, 0.0, 1.0) * body * 0.6;
}
"""
	var drop_mat := ShaderMaterial.new()
	drop_mat.shader = drop_shader
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.028, 0.065)
	_drop_mesh.material = drop_mat
	_streak_mesh = BoxMesh.new()
	_streak_mesh.size = Vector3(0.009, 0.13, 0.009)
	_streak_mesh.material = streak_mat


## Spray of a wheel in water: a fan of droplets thrown up and back, falling back under gravity.
func _splash_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 240
	p.set_meta("budget", 240)
	p.lifetime = 0.75
	p.local_coords = false
	p.mesh = _drop_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.particle_flag_align_y = true   # drops stretched along their flight
	p.direction = Vector3.UP
	p.spread = 40.0
	p.flatness = 0.4
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.18
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.1, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	p.color_ramp = gradient
	add_child(p)
	return p


func _emitter(count: int, duration: float, spark: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = count
	p.set_meta("budget", count)
	p.lifetime = duration
	p.local_coords = false
	p.mesh = _spark_mesh if spark else _smoke_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	p.spread = 38.0
	p.gravity = Vector3(0, -7.5 if spark else 0.25, 0)
	p.initial_velocity_min = 0.8 if spark else 0.25
	p.initial_velocity_max = 3.0 if spark else 0.65
	p.angular_velocity_min = -35.0
	p.angular_velocity_max = 35.0
	p.scale_amount_min = 0.75 if spark else 0.38
	p.scale_amount_max = 1.3 if spark else 0.70
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.10
	p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0)])
	p.color_ramp = gradient
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.35))
	growth.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = growth
	add_child(p)
	return p


func _quality() -> void:
	for p in get_children():
		if not p is CPUParticles3D: continue
		p.amount = maxi(6, int(p.get_meta("budget")) / (2 if int(Game.graphics.get("effects", 1)) == 0 else 1))


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(world):
		return
	var pos := vehicle.get_position_ws()
	var camera := get_viewport().get_camera_3d()
	var near := camera == null or camera.global_position.distance_squared_to(pos) < 110.0 * 110.0
	var teleported := _previous_position.is_finite() and pos.distance_to(_previous_position) > 12.0
	_previous_position = pos
	if not world.paused:
		_surface_timer -= delta * world.time_scale
		if surfaces and _surface_timer <= 0:
			_surface_timer = 0.08
			var wheels: PackedVector3Array = vehicle.get_effect_anchors()["wheels"]
			if _tread == "":
				_tread = str(vehicle.get_info().get("tread", "road"))
			var grip := PackedFloat32Array([1, 1, 1, 1])
			for i in mini(4, wheels.size()):
				wheel_surfaces[i] = surfaces.at(wheels[i])
				grip[i] = surfaces.effective_grip(wheel_surfaces[i], _tread)
			vehicle.set_surface_grip(grip)
			_update_grime(0.08)
	for p in get_children():
		if not p is CPUParticles3D: continue
		p.speed_scale = 0.0 if world.paused else world.time_scale
		if teleported:
			p.emitting = false
			p.restart()
		if not near:
			p.emitting = false
	if world.paused or not near:
		return
	update_effects(vehicle.get_telemetry(), vehicle.get_effect_anchors(), vehicle.get_wheel_slip(), vehicle.get_wheel_load(), delta * world.time_scale)


## Dust on sand, mud on grass and gravel: dirt climbs up the body with speed and time on loose
## ground; rain washes it off slowly.
func _update_grime(dt: float) -> void:
	var loose := 0
	var sand := 0
	for i in 4:
		var kind := String(wheel_surfaces[i]) if i < wheel_surfaces.size() else ""
		if kind in ["sand", "gravel", "grass"]: loose += 1
		if kind == "sand": sand += 1
	var speed := absf(vehicle.get_speed_kmh())
	if loose > 0 and speed > 3.0:
		var target := Color(0.74, 0.62, 0.47) if sand * 2 >= loose else Color(0.34, 0.27, 0.18)
		grime_color = grime_color.lerp(target, 0.02)
		grime = minf(1.0, grime + dt * 0.0045 * loose / 4.0 * clampf(speed / 40.0, 0.25, 1.6))
	var scene := get_tree().current_scene if is_inside_tree() else null
	var weather: Node = scene.get("weather") if scene else null
	var wet := float(weather.get("wetness")) if weather and weather.get("wetness") != null else 0.0
	grime = maxf(0.0, grime - dt * 0.004 * wet)
	if absf(grime - _grime_applied) < 0.01: return
	_grime_applied = grime
	if _paint_materials.is_empty():
		for child in vehicle.get_children():
			if child is MeshInstance3D:
				var m: Material = (child as MeshInstance3D).get_active_material(0)
				if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("car_paint.gdshader"):
					_paint_materials.append(m)
	for m: ShaderMaterial in _paint_materials:
		m.set_shader_parameter("dirt_amount", grime)
		m.set_shader_parameter("dirt_color", grime_color)


func update_effects(t: Dictionary, anchors: Dictionary, slip: PackedFloat32Array, load: PackedFloat32Array, delta: float) -> void:
	_effect_time += delta
	var breeze := Vector3(0.18 + sin(_effect_time * 0.17) * 0.14, 0, cos(_effect_time * 0.11) * 0.16)
	var wheels: PackedVector3Array = anchors["wheels"]
	var radius: float = anchors["radius"]
	var speed := absf(float(t["speed_kmh"]))
	var contacts: PackedVector3Array = anchors.get("contacts", wheels)
	var normals: PackedVector3Array = anchors.get("normals", PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
	_mark_timer -= delta
	var refresh_surface := _mark_timer <= 0
	if refresh_surface: _mark_timer = 0.08
	# A car rebuilt this frame (Werkstatt) has no contact data yet.
	for i in mini(mini(4, wheels.size()), mini(contacts.size(), normals.size())):
		var loose: bool = wheel_surfaces[i] in ["sand", "gravel", "grass"] if surfaces else dirt
		var contact := load[i] if i < load.size() else 0.0
		var sliding := slip[i] if i < slip.size() else 0.0
		var intensity := smoothstep(2.5, 12.0, sliding) * contact
		if loose:
			intensity = maxf(intensity, smoothstep(12, 65, speed) * contact * 0.65)
		# A wheel in water throws spray instead of dust (a ford, the pond's edge).
		var splash := 0.0
		if world and world.has_method("water_depth_at"):
			var wet_depth: float = world.water_depth_at(contacts[i] + Vector3.UP * 0.05)
			if wet_depth > 0.0:
				splash = smoothstep(3.0, 25.0, speed) * clampf(wet_depth / 0.15, 0.3, 1.0)
		if marks and refresh_surface:
			marks.trace("%s:%d" % [vehicle.get_instance_id(), i], contacts[i], normals[i], intensity if not loose and contact > 0.15 else 0.0)
		_levels[i] = lerpf(_levels[i], intensity, 1.0 - exp(-delta * 6.0))
		var p := tires[i]
		p.global_position = contacts[i] + normals[i] * 0.04 if contact > 0.05 else wheels[i] - Vector3.UP * radius
		p.emitting = _levels[i] > 0.10
		p.color = Color(0.67, 0.53, 0.35, _levels[i] * 0.85) if loose else Color(0.83, 0.86, 0.88, _levels[i])
		var sp := splashes[i]
		sp.emitting = splash > 0.05
		if splash > 0.0:
			# Droplets thrown up and back off the tread; the bow wave pushes some forward too.
			sp.global_position = contacts[i] + Vector3.UP * 0.08
			var vel := vehicle.get_velocity()
			sp.direction = (Vector3.UP * 1.2 - vel.normalized() * 0.35).normalized()
			sp.initial_velocity_min = 1.0 + splash * 1.5
			sp.initial_velocity_max = 2.5 + splash * 4.5
			sp.color = Color(0.76, 0.81, 0.80, 1.0)
			sp.speed_scale = 0.8 + 0.4 * splash
			# A light mist round the droplets (the dust emitter, white and faint).
			_levels[i] = lerpf(_levels[i], splash * 0.35, 1.0 - exp(-delta * 6.0))
			p.emitting = _levels[i] > 0.05
			p.color = Color(0.9, 0.93, 0.94, _levels[i] * 0.6)
		# Airflow stretches the emitted wake; existing particles stay in world space.
		p.direction = (normals[i] * 0.65 - vehicle.get_velocity() * 0.035).normalized()
		p.gravity = breeze + Vector3.UP * (-0.12 if loose else 0.25)
		p.initial_velocity_max = 0.6 + _levels[i] * 1.2

		p.scale_amount_max = 0.8 + _levels[i] * 1.1
		var spark := sparks[i]
		spark.global_position = p.global_position
		spark.color = Color(0.39, 0.32, 0.22) if loose else Color(1.0, 0.56, 0.12)
		spark.direction = (normals[i] - vehicle.get_velocity() * 0.10).normalized()
		# Flat rubber alone doesn't spark; only a shredded tyre exposes metal.
		spark.emitting = not loose and bool(t["wheel_burst"][i]) and float(t["tire_wear"][i]) > 0.9 and speed > 18.0 and contact > 0.35
		if wheel_surfaces[i] == "gravel":
			spark.emitting = contact > 0.3 and (speed > 28 or sliding > 4)
	# Bodywork scraping the road: a fan of sparks thrown back from the contact on hard ground.
	var scrape := float(t.get("scrape", 0.0))
	var loose_wheels := 0
	for surface in wheel_surfaces:
		if surface in ["sand", "gravel", "grass"]: loose_wheels += 1
	body_sparks.emitting = scrape > 0.04 and loose_wheels < 2 and speed > 8.0
	if body_sparks.emitting:
		body_sparks.global_position = t.get("scrape_point", vehicle.get_position_ws())
		# Abraded steel leaves with part of the body's own velocity and bounces off the road,
		# so the fan trails just behind the contact instead of shooting backwards.
		var throw := vehicle.get_velocity() * 0.3 + Vector3.UP * 1.6
		body_sparks.direction = throw.normalized()
		body_sparks.initial_velocity_min = throw.length() * 0.55
		body_sparks.initial_velocity_max = throw.length() * 1.05 + 2.0
	var steam := smoothstep(104.0, 130.0, float(t["coolant_temp"])) * maxf(float(t["radiator_damage"]), 1.0 - float(t["coolant_level"]))
	var oil_smoke := float(t["engine_damage"]) * (0.4 if bool(t["running"]) else 0.18)
	oil_smoke *= smoothstep(50.0, 100.0, float(t["oil_temp"]))
	var clutch_smoke := smoothstep(210.0, 330.0, float(t.get("clutch_temp", 45.0)))
	var fire := float(t.get("fire", 0.0))
	var level := maxf(maxf(steam, maxf(oil_smoke, clutch_smoke)), fire)
	engine_smoke.global_position = anchors["engine"]
	engine_smoke.gravity = breeze + Vector3.UP * 0.32
	engine_smoke.direction = (Vector3.UP - vehicle.get_velocity() * 0.035).normalized()
	engine_smoke.emitting = level > 0.06
	engine_smoke.color = Color(0.85, 0.89, 0.92, level) if steam > oil_smoke else Color(0.34, 0.37, 0.40, level)
	if fire > 0.0:
		# A burning car: flames from the engine bay or the tank, thick black smoke, flickering light.
		var at: Vector3 = anchors["exhaust"] if int(t.get("fire_source", 0)) == 1 else anchors["engine"]
		engine_smoke.global_position = at + Vector3.UP * 0.4
		engine_smoke.color = Color(0.05, 0.05, 0.05, 1.0)
		engine_smoke.scale_amount_max = 2.5 + 3.0 * fire
		engine_smoke.initial_velocity_max = 1.6
		engine_smoke.gravity = breeze + Vector3.UP * 1.1
		flames.global_position = at + Vector3.UP * 0.15
		flames.scale_amount_max = 0.45 + 0.7 * fire
		fire_light.global_position = at + Vector3.UP * 0.8
		fire_light.light_energy = (1.5 + 4.0 * fire) * randf_range(0.75, 1.15)
	flames.emitting = fire > 0.02
	if fire <= 0.0:
		fire_light.light_energy = 0.0
	engine_smoke.scale_amount_max = 1.5 + level
	var rings := float(t.get("piston_ring_damage", 0.0))
	var exhaust_level := 0.055 + (0.45 if bool(t["head_gasket"]) else 0.0) + oil_smoke + 0.5 * rings
	exhaust.global_position = anchors["exhaust"]
	exhaust.emitting = bool(t["running"]) and not _electric   # an electric car has no exhaust
	exhaust.direction = -vehicle.get_forward() + Vector3.UP * 0.3
	# Burnt oil from worn rings is blue-grey; steam from a head gasket white.
	exhaust.color = Color(0.75, 0.79, 0.84, exhaust_level).lerp(Color(0.50, 0.56, 0.68, exhaust_level), clampf(rings * 2.0, 0.0, 1.0))
	exhaust.scale_amount_max = 0.40
