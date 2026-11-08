extends SceneTree
## Headless smoke test: godot --headless --path game -s res://tests/smoke_test.gd

func _initialize() -> void:
	var ok := true
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	var lib := {}
	world.material_library = lib
	for path in ["res://cars/kestrel_hatch.car.json", "res://cars/aurora_sedan.car.json", "res://cars/vortex_gt.car.json", "res://cars/basalt_suv.car.json"]:
		var v: SBVehicle = world.spawn_car(path, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
		if v == null:
			print("FAIL spawn ", path)
			ok = false
			continue
		v.set_input(1.0, 0.0, 0.0, 0.0)
		world.step_blocking(4.0)
		world.sync_visuals()
		var t := v.get_telemetry()
		var info := v.get_info()
		print("%s: %.1f km/h, gear %d, %.0f rpm, coolant %.1f C, status '%s', pos %s, children %d" % [info["name"], t["speed_kmh"], t["gear"], t["rpm"], t["coolant_temp"], t["status"], v.get_position_ws(), v.get_child_count()])
		if t["speed_kmh"] < 30.0:
			ok = false
		world.remove_vehicle(v)
	var s := world.get_stats()
	print("stats: ", s)
	print("SMOKE TEST ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)
