extends Node3D
## Slowly rotating wind turbines. The masts are visual-only shapes (they stand far outside the
## driving envelope); the rotor assemblies are children of this node and keep their own phase.

var _rotors: Array[Dictionary] = []
var _blade_mesh: Mesh
var _tip_mesh: Mesh

func _ready() -> void:
	_blade_mesh = CylinderMesh.new()
	_blade_mesh.bottom_radius = 0.48
	_blade_mesh.top_radius = 0.16
	_blade_mesh.height = 18.2
	_blade_mesh.radial_segments = 8
	_tip_mesh = CylinderMesh.new()
	_tip_mesh.bottom_radius = 0.17
	_tip_mesh.top_radius = 0.11
	_tip_mesh.height = 2.8
	_tip_mesh.radial_segments = 8

func add_turbine(p: Vector3, white: Material, metal: Material, red: Material, phase: float) -> void:
	if _blade_mesh == null:
		_ready()
	var mast := MeshInstance3D.new()
	var mast_mesh := CylinderMesh.new()
	mast_mesh.bottom_radius = 1.15
	mast_mesh.top_radius = 0.62
	mast_mesh.height = 50.0
	mast_mesh.radial_segments = 12
	mast.mesh = mast_mesh
	mast.material_override = white
	mast.position = p + Vector3.UP * 25.0
	add_child(mast)
	var nacelle := MeshInstance3D.new()
	var nacelle_mesh := BoxMesh.new()
	nacelle_mesh.size = Vector3(5.4, 3.0, 3.8)
	nacelle.mesh = nacelle_mesh
	nacelle.material_override = metal
	nacelle.position = p + Vector3(0, 50, -0.8)
	add_child(nacelle)
	var rotor := Node3D.new()
	rotor.position = p + Vector3(0, 50, -3.2)
	rotor.rotation.z = phase
	add_child(rotor)
	for blade in 3:
		var angle := TAU / 3.0 * blade
		var direction := Vector3(-sin(angle), cos(angle), 0)
		var mi := MeshInstance3D.new()
		mi.mesh = _blade_mesh
		mi.material_override = white
		mi.position = direction * 9.1
		mi.rotation.z = angle
		mi.scale = Vector3(1.0, 1.0, 0.32)
		rotor.add_child(mi)
		var tip := MeshInstance3D.new()
		tip.mesh = _tip_mesh
		tip.material_override = red
		tip.position = direction * 19.3
		tip.rotation.z = angle
		tip.scale = Vector3(1.0, 1.0, 0.32)
		rotor.add_child(tip)
	_rotors.append({"node": rotor, "speed": 0.38 + 0.04 * sin(phase * 3.7)})

func _process(delta: float) -> void:
	for entry in _rotors:
		var rotor: Node3D = entry["node"]
		rotor.rotation.z += float(entry["speed"]) * delta
