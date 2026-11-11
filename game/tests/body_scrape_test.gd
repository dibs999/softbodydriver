extends SceneTree
## Body scraping telemetry (drives the grinding sound and the spark fan): it stays silent while a
## car accelerates, brakes and corners hard on its wheels, and it fires when the car drives over a
## 24 cm kerb block at speed and the floor and front end hit the obstacle.
## godot --headless -s res://tests/body_scrape_test.gd
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _peak(world: SBWorld, car: SBVehicle, seconds: float, steer: float, brake_after: float) -> float:
	var peak := 0.0
	for i in int(seconds / 0.01):
		var t := i * 0.01
		if t > brake_after:
			car.set_input(0.0, 1.0, steer, 0)
		world.step_blocking(0.01)
		world.sync_visuals()
		peak = maxf(peak, float(car.get_telemetry()["scrape"]))
	return peak

func _initialize() -> void:
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	# Clean driving: full throttle, a hard turn, then an emergency stop.
	var a := world.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	world.step_blocking(0.6)
	a.set_input(1.0, 0, 0, 0)
	var clean := _peak(world, a, 4.0, 0.0, 99.0)
	a.set_input(0.6, 0, 0.7, 0)
	clean = maxf(clean, _peak(world, a, 2.0, 0.7, 1.2))
	print("  clean driving: peak scrape %.3f at %.0f km/h" % [clean, a.get_speed_kmh()])
	check(clean < 0.04, "No scraping while the car is on its wheels")
	# A 24 cm block across the road: the bumper and floor grind over it.
	var w2 := SBWorld.new()
	w2.paused = true
	root.add_child(w2)
	w2.add_ground_plane(1.0)
	w2.add_box(Vector3(45, 0.12, 0), Vector3(1.5, 0.12, 6.0), Vector3.ZERO, 0.6)
	var b := w2.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	w2.step_blocking(0.6)
	b.set_input(1.0, 0, 0, 0)
	var hit := _peak(w2, b, 7.0, 0.0, 99.0)
	print("  over the block: peak scrape %.3f" % hit)
	check(hit > 0.2, "Hitting the block registers body scraping")
	print("TEST FAILED" if failed else "TEST PASSED")
	quit(1 if failed else 0)
