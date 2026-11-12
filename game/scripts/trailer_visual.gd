extends Node3D
## Looks of the box trailer prop (sbcore PropKind::Trailer), built in the prop's rest coordinates:
## +x points along the drawbar to the hitch, the bed is 2.4 x 1.4 m at 0.56 m, its walls 0.36 m
## high. The wheels follow the simulated tyres every frame; the rear lamps show the towing car's
## tail lights, brake lights and indicators.

var prop: SBProp
var towing: SBVehicle
var lamp_state: Dictionary = {}   # the towing car's lamp state (vehicle_equipment)
var _wheels: Array[Node3D] = []
var _tail: Array[StandardMaterial3D] = []
var _signal_l: StandardMaterial3D
var _signal_r: StandardMaterial3D
var _blink := 0.0


func _init(p: SBProp) -> void:
	prop = p
	name = "TrailerVisual"


static func _mat(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	add_child(mi)
	return mi


func _ready() -> void:
	var galv := _mat(Color(0.62, 0.64, 0.66), 0.35, 0.8)     # galvanised steel
	var panel := _mat(Color(0.70, 0.72, 0.74), 0.45, 0.6)
	var dark := _mat(Color(0.10, 0.10, 0.11), 0.8)
	var deck := _mat(Color(0.30, 0.24, 0.18), 0.9)            # phenolic plywood floor
	# Chassis: two longitudinal members, cross members, the floor.
	for z: float in [-0.55, 0.55]:
		_box(Vector3(2.4, 0.08, 0.06), Vector3(0, 0.46, z), galv)
	for x: float in [-1.15, -0.4, 0.4, 1.15]:
		_box(Vector3(0.05, 0.06, 1.36), Vector3(x, 0.47, 0), galv)
	_box(Vector3(2.4, 0.03, 1.38), Vector3(0, 0.545, 0), deck)
	# Side and end walls: ribbed steel boards with a top rail and corner posts.
	for z: float in [-0.695, 0.695]:
		_box(Vector3(2.4, 0.34, 0.012), Vector3(0, 0.74, z), panel)
		for k in 6:
			_box(Vector3(2.4, 0.012, 0.02), Vector3(0, 0.6 + k * 0.055, z * 1.004), galv)
		_box(Vector3(2.42, 0.04, 0.04), Vector3(0, 0.92, z), galv)
	for x: float in [-1.2, 1.2]:
		_box(Vector3(0.012, 0.34, 1.4), Vector3(x, 0.74, 0), panel)
		_box(Vector3(0.04, 0.04, 1.42), Vector3(x, 0.92, 0), galv)
	for x: float in [-1.2, 1.2]:
		for z: float in [-0.7, 0.7]:
			_box(Vector3(0.05, 0.40, 0.05), Vector3(x, 0.74, z), galv)
	# A-frame drawbar and the coupling head with its handle.
	for side: float in [-1.0, 1.0]:
		var a := Vector3(1.2, 0.44, side * 0.62)
		var b := Vector3(2.2, 0.45, side * 0.04)
		var bar := _box(Vector3(a.distance_to(b), 0.07, 0.06), (a + b) * 0.5, galv)
		bar.rotation.y = -atan2(b.z - a.z, b.x - a.x)
	_box(Vector3(0.22, 0.09, 0.10), Vector3(2.28, 0.47, 0), dark)
	_box(Vector3(0.14, 0.03, 0.04), Vector3(2.26, 0.54, 0), dark, Vector3(0, 0, 0.3))
	_box(Vector3(0.06, 0.32, 0.06), Vector3(1.85, 0.28, 0.0), dark)   # jockey wheel post
	# Mudguards over the wheels.
	for z: float in [-0.70, 0.70]:
		var guard := _box(Vector3(0.78, 0.02, 0.22), Vector3(-0.15, 0.66, z * 1.0), dark)
		guard.position.z = z + signf(z) * 0.0
	# Rear: lamp bar, plate, triangle reflectors.
	var lamp_bar := _box(Vector3(0.05, 0.08, 1.5), Vector3(-1.24, 0.47, 0), dark)
	lamp_bar.name = "LampBar"
	for z: float in [-0.62, 0.62]:
		var red := _mat(Color(0.55, 0.03, 0.03), 0.3)
		red.emission_enabled = true
		red.emission = Color(1.0, 0.08, 0.04)
		red.emission_energy_multiplier = 0.0
		_tail.append(red)
		_box(Vector3(0.03, 0.06, 0.16), Vector3(-1.27, 0.47, z), red)
		var amber := _mat(Color(0.6, 0.35, 0.05), 0.3)
		amber.emission_enabled = true
		amber.emission = Color(1.0, 0.55, 0.1)
		amber.emission_energy_multiplier = 0.0
		if z < 0: _signal_l = amber
		else: _signal_r = amber
		_box(Vector3(0.03, 0.06, 0.07), Vector3(-1.27, 0.47, z + signf(z) * 0.115), amber)
		_box(Vector3(0.01, 0.07, 0.07), Vector3(-1.265, 0.38, z), _mat(Color(0.7, 0.05, 0.03), 0.2), Vector3(PI * 0.25, 0, 0))
	_box(Vector3(0.01, 0.11, 0.52), Vector3(-1.27, 0.62, 0), _mat(Color(0.95, 0.95, 0.92), 0.4))   # plate
	# Wheels: steel rim and tyre; they follow the simulated tyres (see _process).
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.29
	tyre.bottom_radius = 0.29
	tyre.height = 0.155
	tyre.radial_segments = 28
	var rim := CylinderMesh.new()
	rim.top_radius = 0.17
	rim.bottom_radius = 0.17
	rim.height = 0.165
	rim.radial_segments = 20
	var rubber := _mat(Color(0.06, 0.06, 0.06), 0.95)
	var steel := _mat(Color(0.75, 0.76, 0.78), 0.35, 0.8)
	for i in prop.get_wheel_transforms().size():
		var w := Node3D.new()
		w.top_level = true
		var t := MeshInstance3D.new()
		t.mesh = tyre
		t.material_override = rubber
		w.add_child(t)
		var r := MeshInstance3D.new()
		r.mesh = rim
		r.material_override = steel
		w.add_child(r)
		var nut := BoxMesh.new()
		nut.size = Vector3(0.05, 0.17, 0.05)
		var spoke := MeshInstance3D.new()   # shows the wheel turning
		spoke.mesh = nut
		spoke.material_override = _mat(Color(0.3, 0.3, 0.32), 0.5, 0.6)
		spoke.position = Vector3(0.09, 0, 0)
		w.add_child(spoke)
		add_child(w)
		_wheels.append(w)


func _process(delta: float) -> void:
	var xfs := prop.get_wheel_transforms()
	for i in mini(xfs.size(), _wheels.size()):
		_wheels[i].global_transform = xfs[i]
	var lights := not lamp_state.is_empty() and bool(lamp_state.get("lights", false))
	var braking := is_instance_valid(towing) and float(towing.get_telemetry().get("brake", 0.0)) > 0.05
	for m in _tail:
		m.emission_energy_multiplier = 3.5 if braking else (0.8 if lights else 0.0)
	_blink = fmod(_blink + delta, 0.8)
	var on := _blink < 0.4
	var sig := int(lamp_state.get("signal", 0)) if not lamp_state.is_empty() else 0
	var hazards := not lamp_state.is_empty() and bool(lamp_state.get("hazards", false))
	_signal_l.emission_energy_multiplier = 3.0 if on and (hazards or sig == -1) else 0.0
	_signal_r.emission_energy_multiplier = 3.0 if on and (hazards or sig == 1) else 0.0
