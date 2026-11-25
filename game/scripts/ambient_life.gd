extends Node3D
## Lightweight ambient bird flocks. They are deliberately simple dark silhouettes: at their height
## and speed the moving wing shapes sell more life than detailed geometry would.

var _birds: Array[Dictionary] = []
var _body_mesh: BoxMesh
var _left_wing: ArrayMesh
var _right_wing: ArrayMesh
var _material: StandardMaterial3D

const MAP_FLOCKS := {
	"city": [{"center": Vector3(0, 52, 0), "radius": 150.0, "count": 5}],
	"autobahn": [{"center": Vector3(-250, 68, -120), "radius": 230.0, "count": 6}],
	"offroad": [{"center": Vector3(-80, 54, 80), "radius": 190.0, "count": 6}, {"center": Vector3(260, 70, -220), "radius": 160.0, "count": 4}],
	"hill_roads": [{"center": Vector3(0, 72, 0), "radius": 230.0, "count": 6}],
	"desert": [{"center": Vector3(120, 58, -80), "radius": 220.0, "count": 5}],
	"proving_grounds": [{"center": Vector3(0, 44, 0), "radius": 110.0, "count": 4}],
}

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.055, 0.065, 0.055)
	_material.roughness = 0.9
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_body_mesh = BoxMesh.new()
	_body_mesh.size = Vector3(0.12, 0.08, 0.42)
	_left_wing = _wing_mesh(-1.0)
	_right_wing = _wing_mesh(1.0)

func _wing_mesh(side: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0.10), Vector3(side * 0.62, 0, 0.02), Vector3(side * 0.42, 0, -0.22),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func configure(map_id: String) -> void:
	for child in get_children():
		child.queue_free()
	_birds.clear()
	if _material == null:
		_ready()
	var rng := RandomNumberGenerator.new()
	rng.seed = map_id.hash()
	for flock: Dictionary in MAP_FLOCKS.get(map_id, []):
		for i in int(flock["count"]):
			_add_bird(flock["center"], float(flock["radius"]) * rng.randf_range(0.78, 1.12), rng)

func _add_bird(center: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var bird := Node3D.new()
	add_child(bird)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.material_override = _material
	bird.add_child(body)
	var left := MeshInstance3D.new()
	left.mesh = _left_wing
	left.material_override = _material
	bird.add_child(left)
	var right := MeshInstance3D.new()
	right.mesh = _right_wing
	right.material_override = _material
	bird.add_child(right)
	_birds.append({
		"node": bird, "left": left, "right": right, "center": center + Vector3(rng.randfn() * 12, rng.randf_range(-5, 8), rng.randfn() * 12),
		"radius": radius, "phase": rng.randf() * TAU, "speed": rng.randf_range(7.5, 11.5), "flap": rng.randf() * TAU,
	})

func _process(delta: float) -> void:
	for entry in _birds:
		entry["phase"] = float(entry["phase"]) + float(entry["speed"]) * delta / float(entry["radius"])
		var angle := float(entry["phase"])
		var center: Vector3 = entry["center"]
		var radius := float(entry["radius"])
		var bird: Node3D = entry["node"]
		var pos := center + Vector3(cos(angle) * radius, sin(angle * 2.3) * 3.0, sin(angle) * radius)
		bird.position = pos
		bird.look_at(pos + Vector3(-sin(angle), 0.0, cos(angle)), Vector3.UP)
		entry["flap"] = float(entry["flap"]) + delta * 9.0
		var flap := sin(float(entry["flap"])) * 0.55
		(entry["left"] as Node3D).rotation.z = -flap
		(entry["right"] as Node3D).rotation.z = flap
