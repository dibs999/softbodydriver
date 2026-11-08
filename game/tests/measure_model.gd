extends SceneTree
## Prints the bounds of every top-level part of a glTF model: godot --headless -s res://tests/measure_model.gd -- res://models/x.glb

func _initialize() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var scene: Node3D = load(path).instantiate()
	var total := AABB()
	var first := true
	_walk(scene, Transform3D.IDENTITY, 0)
	quit()

func _walk(n: Node, xf: Transform3D, depth: int) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = x * (n as MeshInstance3D).mesh.get_aabb()
		if depth <= 3 or n.name.begins_with("Wheel"):
			print("%-32s pos %s size %s" % [n.name, a.position.snapped(Vector3.ONE * 0.001), a.size.snapped(Vector3.ONE * 0.001)])
	for c in n.get_children():
		_walk(c, x, depth + 1)
