extends SceneTree
## Number plates: both procedural and imported cars carry a front and a rear plate on the body's
## plate anchors, facing outward, with a German-style registration.
var failures := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	var game := root.get_node("Game")
	var Plates := preload("res://scripts/vehicle_plates.gd")
	var re := RegEx.new()
	re.compile("^[A-ZÄÖÜ]{1,3}·[A-Z]{1,2} [1-9][0-9]{0,3}$")
	var all_ok := true
	for seed_value in 50:
		all_ok = all_ok and re.search(Plates.plate_text(seed_value)) != null
	check(all_ok, "Registrations look like German plates (e.g. %s)" % Plates.plate_text(7))
	check(Plates.plate_text(3) == Plates.plate_text(3) and Plates.plate_text(3) != Plates.plate_text(4), "Registrations are deterministic per seed and differ between cars")
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	var x := 0.0
	for path in ["res://cars/kestrel_hatch.car.json", "res://cars/meridian_sedan.car.json"]:
		var v: SBVehicle = game.spawn_vehicle(world, path, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
		x += 8.0
		world.step_blocking(0.5)
		world.sync_visuals()
		var plates: Node3D = v.get_node("Plates")
		if not plates.is_node_ready():
			plates._ready()
		plates._process(0.0)
		var xf: Array = v.get_plate_transforms()
		check(xf.size() == 2 and plates.visible, "%s has front and rear plate anchors" % path.get_file())
		if xf.size() != 2:
			continue
		var centre := v.get_position_ws()
		var fwd := v.get_forward()
		var front: Transform3D = xf[0]
		var rear: Transform3D = xf[1]
		check((front.origin - centre).dot(fwd) > 1.5 and (rear.origin - centre).dot(fwd) < -1.5, "%s: plates at the front and rear ends" % path.get_file())
		check(front.basis.z.dot(fwd) > 0.95 and rear.basis.z.dot(fwd) < -0.95, "%s: plates face outward" % path.get_file())
		check(front.origin.y > 0.15 and front.origin.y < 0.8 and rear.origin.y > 0.3 and rear.origin.y < 1.1, "%s: plates at bumper / boot height" % path.get_file())
	world.free()
	print("PLATES TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
