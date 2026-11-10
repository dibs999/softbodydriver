extends SceneTree
## Physical latch release, repeat protection and repair through the GDExtension.
var failures := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	var car := world.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D.IDENTITY)
	check(car != null, "Reference car spawns")
	if car == null:
		quit(1)
		return
	car.set_input(0, 1, 0, 1)
	world.step_blocking(1.0)
	world.sync_visuals()
	check(car.release_bonnet(), "Intact latch releases")
	check(not car.release_bonnet(), "Repeated action cannot add opening energy")
	world.step_blocking(0.3)
	world.sync_visuals()
	check(car.get_position_ws().is_finite() and car.get_velocity().is_finite(), "Vehicle remains finite with released panel")
	check(int(car.get_telemetry()["broken_beams"]) == 0, "Opening is a mechanism, nothing breaks")
	check(not bool(car.get_lid_states()[0]["latched"]), "Latch let go")
	world.step_blocking(5.0)
	world.sync_visuals()
	check(car.get_velocity().is_finite() and int(car.get_telemetry()["broken_beams"]) == 0, "Ramped physical supports hold the open bonnet without destroying hinges")
	check(car.close_bonnet(), "Open bonnet can be closed")
	world.step_blocking(5.0)
	world.sync_visuals()
	check(bool(car.get_lid_states()[0]["latched"]), "Closed bonnet relatches without a repair")
	check(car.release_bonnet(), "Relatched bonnet opens again")
	car.repair_in_place()
	world.step_blocking(0.01)
	world.sync_visuals()
	check(int(car.get_telemetry()["broken_beams"]) == 0 and bool(car.get_lid_states()[0]["latched"]), "Repair shuts and latches the bonnet")
	car.set_input(1, 0, 0, 0)
	world.step_blocking(4.0)
	world.sync_visuals()
	check(car.get_speed_kmh() > 10 and not car.release_bonnet(), "Manual bonnet opening is rejected while driving")
	world.remove_vehicle(car)
	world.free()
	print("BONNET TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
