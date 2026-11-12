extends Node3D
## Windscreen rain and wipers for the player vehicle. The pane and two tandem wiper arms are placed
## from the body profile (same frame as the weather's cabin shelter) and follow the vehicle every
## frame. Modes: automatic (runs in rain), off, continuous. The rain shader works out from the wiper
## cycle where the blades have last passed.

const RAIN_SHADER := preload("res://materials/windscreen_rain.gdshader")
const MODE_NAMES := ["Automatik", "Aus", "Dauerbetrieb"]
const PERIOD := 1.25
const SWEEP := 1.85

var mode := 0
var running := false
var cycles := 0.0
var off_time := 1000.0
var _stopping := false
var _vehicle: SBVehicle
## Renders and tests: speed in km/h the drops react to instead of the car's (< 0: the car's).
var speed_override := -1.0
var _flow_a := 0.0
var _flow_b := 0.0
var _pane: MeshInstance3D
var _material: ShaderMaterial
var _arms: Array[MeshInstance3D] = []
var _plane := {}        # bottom centre, unit vectors along/lateral/normal, pivots, radii


func attach(vehicle: SBVehicle, body: Dictionary, draw_arms := true) -> void:
	for child in get_children():
		child.queue_free()
	_arms.clear()
	_vehicle = vehicle
	if not is_instance_valid(vehicle) or body.is_empty():
		_vehicle = null
		return
	top_level = true
	var length := float(body.get("length", 4.26))
	var origin_x := length - float(body.get("frontOverhang", 0.89)) - float(body.get("wheelbase", 2.62)) * 0.5
	var origin_y := float(body.get("groundClearance", 0.14)) + 0.04
	var front := length - float(body.get("hoodLength", 1.15)) - origin_x
	var front_top := front - float(body.get("windshieldRun", 0.80))
	var width := float(body.get("width", 1.79))
	var bottom := Vector3(front - 0.03, float(body.get("hoodHeight", 0.98)) - origin_y + 0.02, 0.0)
	var top := Vector3(front_top + 0.05, float(body.get("height", 1.45)) - origin_y - 0.06, 0.0)
	var hb := width * 0.5 - 0.24
	var ht := width * 0.5 * float(body.get("roofWidthRatio", 0.78)) - 0.16
	var along := (top - bottom).normalized()
	var lateral := Vector3(0, 0, 1)
	var normal := along.cross(lateral).normalized()
	if normal.y < 0.0:
		normal = -normal
	var span := bottom.distance_to(top)
	# Pane slightly outside the glass so drops are drawn on top of it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := normal * 0.012
	var corners := [[bottom - lateral * hb, Vector2(0, 1), Vector2(-hb, 0)], [bottom + lateral * hb, Vector2(1, 1), Vector2(hb, 0)],
		[top + lateral * ht, Vector2(1, 0), Vector2(ht, span)], [top - lateral * ht, Vector2(0, 0), Vector2(-ht, span)]]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_uv(corners[i][1])
		st.set_uv2(corners[i][2])
		st.set_normal(normal)
		st.add_vertex(corners[i][0] + lift)
	_pane = MeshInstance3D.new()
	_pane.mesh = st.commit()
	_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = RAIN_SHADER
	_pane.material_override = _material
	add_child(_pane)
	var pivots := [Vector2(-hb * 0.02, 0.035), Vector2(hb * 0.8, 0.035)]
	var radii := [Vector2(hb * 0.22, hb * 1.0), Vector2(hb * 0.2, hb * 0.9)]
	_plane = {"bottom": bottom, "along": along, "lateral": lateral, "normal": normal, "pivots": pivots, "radii": radii}
	_material.set_shader_parameter("pivot_a", pivots[0])
	_material.set_shader_parameter("pivot_b", pivots[1])
	_material.set_shader_parameter("radius_a", radii[0])
	_material.set_shader_parameter("radius_b", radii[1])
	_material.set_shader_parameter("sweep", SWEEP)
	_material.set_shader_parameter("period", PERIOD)
	if draw_arms:
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.03, 0.03, 0.035)
		dark.roughness = 0.45
		dark.metallic = 0.4
		for k in 2:
			var arm := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			var r: Vector2 = radii[k]
			mesh.size = Vector3(r.y, 0.008, 0.011)
			arm.mesh = mesh
			arm.material_override = dark
			var blade := MeshInstance3D.new()
			var blade_mesh := BoxMesh.new()
			blade_mesh.size = Vector3(r.y - r.x, 0.014, 0.012)
			blade.mesh = blade_mesh
			blade.material_override = dark
			blade.position = Vector3((r.x + r.y) * 0.5 - r.y * 0.5, -0.008, 0)
			arm.add_child(blade)
			add_child(arm)
			_arms.append(arm)
	_update_transforms()


func cycle_mode() -> String:
	mode = (mode + 1) % MODE_NAMES.size()
	return "Scheibenwischer: " + MODE_NAMES[mode]


func update(delta: float, raining: bool, wetness: float) -> void:
	if not is_instance_valid(_vehicle):
		visible = false
		return
	visible = true
	var want := mode == 2 or (mode == 0 and (raining or wetness > 0.35))
	if want and not running:
		# The glass kept collecting rain while the blades were parked.
		_material.set_shader_parameter("pre_time", off_time)
		running = true
		_stopping = false
		cycles = 0.0
		off_time = 0.0
	elif not want and running:
		_stopping = true
	if running:
		var next := cycles + delta / PERIOD
		if _stopping and floor(next) > floor(cycles):
			cycles = floor(next)          # park at the end of the sweep
			running = false
			_stopping = false
		else:
			cycles = next
	else:
		off_time += delta
	_material.set_shader_parameter("cycles", cycles)
	_material.set_shader_parameter("off_time", 0.0 if running else off_time)
	# Drops run along the glass: large ones creep down under gravity when slow; from ~55 km/h the
	# airflow pushes them up and out, faster the faster the car goes (small drops cling longer).
	var kmh := speed_override if speed_override >= 0.0 else absf(_vehicle.get_speed_kmh())
	var air := smoothstep(50.0, 130.0, kmh)
	var run := (-0.010 + 0.34 * air) * delta * (1.0 if wetness > 0.01 else 0.0)
	_flow_a = fposmod(_flow_a + run, 22.0)          # wrap on whole drop cells (0.022 m)
	_flow_b = fposmod(_flow_b + run * 0.45, 11.0)   # (0.011 m)
	_material.set_shader_parameter("flow_a", _flow_a)
	_material.set_shader_parameter("flow_b", _flow_b)
	_material.set_shader_parameter("stretch", smoothstep(55.0, 120.0, kmh))
	_material.set_shader_parameter("rain", 1.0 if raining else 0.0)
	_material.set_shader_parameter("wetness", wetness)
	_update_transforms()


func blade_angle() -> float:
	# 0 = parked along the cowl, SWEEP = fully raised.
	return SWEEP * (1.0 - cos(TAU * fposmod(cycles, 1.0))) * 0.5


func _update_transforms() -> void:
	if not is_instance_valid(_vehicle):
		return
	var b := _vehicle.get_visual_basis()
	global_transform = Transform3D(Basis(-b.z, b.y, b.x), _vehicle.get_position_ws())
	if _arms.is_empty():
		return
	var along: Vector3 = _plane.along
	var lateral: Vector3 = _plane.lateral
	var normal: Vector3 = _plane.normal
	var angle := PI - blade_angle()
	var dir := lateral * cos(angle) + along * sin(angle)
	var side := dir.cross(normal).normalized()
	for k in _arms.size():
		var pivot: Vector2 = _plane.pivots[k]
		var r: Vector2 = _plane.radii[k]
		var base: Vector3 = _plane.bottom + lateral * pivot.x + along * pivot.y + normal * 0.03
		_arms[k].transform = Transform3D(Basis(dir, normal, side), base + dir * r.y * 0.5)
