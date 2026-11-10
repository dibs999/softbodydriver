extends Node3D
## Bounded particle pools: world-space smoke remains behind the moving vehicle.
## No physics objects, no per-frame image creation, reduced budget on Performance.

var vehicle: SBVehicle
var world: SBWorld
var dirt := false
var surfaces: RefCounted
var marks: MultiMeshInstance3D
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
var engine_smoke: CPUParticles3D
var exhaust: CPUParticles3D
var _previous_position := Vector3.INF
var _levels := PackedFloat32Array([0, 0, 0, 0])
static var _smoke_mesh: QuadMesh
static var _spark_mesh: SphereMesh


func _ready() -> void:
	if _smoke_mesh == null:
		_make_meshes()
	for i in 4:
		tires.append(_emitter(48, 2.8, false))
		sparks.append(_emitter(10, 0.35, true))
	engine_smoke = _emitter(64, 3.8, false)
	exhaust = _emitter(18, 0.8, false)
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
	for p: CPUParticles3D in get_children():
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
			var grip := PackedFloat32Array([1, 1, 1, 1])
			for i in mini(4, wheels.size()):
				wheel_surfaces[i] = surfaces.at(wheels[i])
				grip[i] = surfaces.effective_grip(wheel_surfaces[i])
			vehicle.set_surface_grip(grip)
			_update_grime(0.08)
	for p: CPUParticles3D in get_children():
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
	for i in mini(4, wheels.size()):
		var loose: bool = wheel_surfaces[i] in ["sand", "gravel", "grass"] if surfaces else dirt
		var contact := load[i] if i < load.size() else 0.0
		var sliding := slip[i] if i < slip.size() else 0.0
		var intensity := smoothstep(2.5, 12.0, sliding) * contact
		if loose:
			intensity = maxf(intensity, smoothstep(12, 65, speed) * contact * 0.65)
		if marks and refresh_surface:
			marks.trace("%s:%d" % [vehicle.get_instance_id(), i], contacts[i], normals[i], intensity if not loose and contact > 0.15 else 0.0)
		_levels[i] = lerpf(_levels[i], intensity, 1.0 - exp(-delta * 6.0))
		var p := tires[i]
		p.global_position = contacts[i] + normals[i] * 0.04 if contact > 0.05 else wheels[i] - Vector3.UP * radius
		p.emitting = _levels[i] > 0.10
		p.color = Color(0.67, 0.53, 0.35, _levels[i] * 0.85) if loose else Color(0.83, 0.86, 0.88, _levels[i])
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
	var steam := smoothstep(104.0, 130.0, float(t["coolant_temp"])) * maxf(float(t["radiator_damage"]), 1.0 - float(t["coolant_level"]))
	var oil_smoke := float(t["engine_damage"]) * (0.4 if bool(t["running"]) else 0.18)
	oil_smoke *= smoothstep(50.0, 100.0, float(t["oil_temp"]))
	var clutch_smoke := smoothstep(210.0, 330.0, float(t.get("clutch_temp", 45.0)))
	var level := maxf(steam, maxf(oil_smoke, clutch_smoke))
	engine_smoke.global_position = anchors["engine"]
	engine_smoke.gravity = breeze + Vector3.UP * 0.32
	engine_smoke.direction = (Vector3.UP - vehicle.get_velocity() * 0.035).normalized()
	engine_smoke.emitting = level > 0.06
	engine_smoke.color = Color(0.85, 0.89, 0.92, level) if steam > oil_smoke else Color(0.34, 0.37, 0.40, level)
	engine_smoke.scale_amount_max = 1.5 + level
	var exhaust_level := 0.055 + (0.45 if bool(t["head_gasket"]) else 0.0) + oil_smoke
	exhaust.global_position = anchors["exhaust"]
	exhaust.emitting = bool(t["running"])
	exhaust.direction = -vehicle.get_forward() + Vector3.UP * 0.3
	exhaust.color = Color(0.75, 0.79, 0.84, exhaust_level)
	exhaust.scale_amount_max = 0.40
