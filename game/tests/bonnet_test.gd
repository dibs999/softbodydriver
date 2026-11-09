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
	check(int(car.get_telemetry()["broken_beams"]) >= 6, "Six latch mounts actually break in physics")
	world.step_blocking(5.0)
	world.sync_visuals()
	check(car.get_velocity().is_finite() and int(car.get_telemetry()["broken_beams"]) == 6, "Ramped physical supports hold the open bonnet without destroying hinges")
	car.repair_in_place()
	world.step_blocking(0.01)
	world.sync_visuals()
	check(int(car.get_telemetry()["broken_beams"]) == 0, "Repair resets support extension and fresh latch remains intact")
	check(car.release_bonnet(), "Repair restores a releasable physical latch")
	car.repair_in_place()
	car.set_input(1, 0, 0, 0)
	world.step_blocking(4.0)
	world.sync_visuals()
	check(car.get_speed_kmh() > 10 and not car.release_bonnet(), "Manual bonnet opening is rejected while driving")
	world.remove_vehicle(car)
	world.free()
	print("BONNET TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
