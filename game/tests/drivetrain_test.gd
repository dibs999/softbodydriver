extends SceneTree
## Native bridge regression: controls, mechanical telemetry, puncture and repair.
## godot --headless --path game -s res://tests/drivetrain_test.gd

var failed := false
var world: SBWorld

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	print(description, ": ", condition)
	if not condition:
		failed = true
		push_error(description)

func advance(seconds: float) -> void:
	world.step_blocking(seconds)
	world.sync_visuals()

func run() -> void:
	world = SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	var car := world.spawn_car("res://cars/vortex_gt.car.json", Transform3D.IDENTITY)
	advance(1.0)
	car.set_input(1, 0, 0, 0)
	advance(8.0)
	var t := car.get_telemetry()
	check(t["speed_kmh"] > 85 and t["gear"] >= 3, "Normal acceleration and automatic shifting")
	check(t["clutch_wear"] == 0 and t["gearbox_damage"] == 0, "Healthy driving causes no drivetrain damage")
	car.set_automatic(false)
	car.set_clutch(1.0)
	car.set_gear(1)
	advance(0.02)
	t = car.get_telemetry()
	check(t["gearbox_damage"] > 0.04, "Loaded downshift reaches damage simulation")
	check(t["shift_remaining"] > 0 and t["gear_grind"] > 0, "Shift interruption and grind reach audio telemetry")
	car.set_input(0, 1, 0, 1)
	car.set_clutch(-1)
	car.repair_in_place()
	advance(0.8)
	t = car.get_telemetry()
	check(t["gearbox_damage"] == 0 and t["clutch_wear"] == 0 and t["shift_remaining"] == 0, "Repair resets drivetrain state")
	car.puncture_tire(0, 8.0)
	advance(7.0)
	t = car.get_telemetry()
	check(t["tire_pressure"][0] < 1.0 and t["tire_pressure"][1] > 25, "Puncture affects only selected wheel")
	var anchors := car.get_effect_anchors()
	check(anchors["wheels"].size() == 4 and anchors["engine"].is_finite(), "Particle anchors are valid")
	car.repair_in_place()
	advance(0.1)
	check(car.get_telemetry()["tire_pressure"][0] > 25, "Repair restores pressure")
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
