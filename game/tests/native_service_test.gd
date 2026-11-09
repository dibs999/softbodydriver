extends SceneTree
## Native recovery must move an already crashed car without secretly repairing it.
var failures := 0

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition:
		failures += 1

func _initialize() -> void:
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	world.add_box(Vector3(20, 0.8, 0), Vector3(0.5, 0.8, 3), Vector3.ZERO, 1.0)
	var car := world.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D.IDENTITY)
	car.set_input(1, 0, 0, 0)
	world.step_blocking(6.0)
	car.set_input(0, 1, 0, 1)
	car.set_ignition(false)
	world.step_blocking(1.0)
	world.sync_visuals()
	var before := car.get_telemetry()
	check(int(before["deformed_beams"]) > 0, "Fixture has real crash deformation")
	var position_before := car.get_position_ws()
	check(not car.relocate_to(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2), Vector3.ZERO)), "Scaled recovery rejected")
	check(not car.relocate_to(Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))), "Nonfinite recovery rejected")
	check(car.get_position_ws().is_equal_approx(position_before), "Invalid recovery leaves position untouched")
	var destination := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1000, 0, 100))
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(500, 0, 500)))
	check(car.relocate_to(destination), "Recovery accepts rigid rotation and translation")
	var recovered := car.get_telemetry()
	check(absf(car.get_position_ws().x - 1000) < 0.01 and absf(car.get_position_ws().z - 100) < 0.01, "Recovery uses requested ground-origin position")
	check(car.get_velocity().length() < 0.000001, "Recovery zeros velocity immediately")
	check(recovered["deformed_beams"] == before["deformed_beams"], "Recovery preserves plastic deformation")
	check(recovered["broken_beams"] == before["broken_beams"], "Recovery preserves broken mounts")
	check(recovered["fuel_l"] == before["fuel_l"], "Recovery preserves actual tank contents")
	check(recovered["coolant_level"] == before["coolant_level"], "Recovery preserves cooling damage state")
	world.step_blocking(0.001)
	world.sync_visuals()
	check(car.get_position_ws().distance_to(Vector3(1000, car.get_position_ws().y, 100)) < 0.05, "Queued sandbox reset cannot undo recovery")
	var fuel_before_service: float = car.get_telemetry()["fuel_l"]
	car.start_engine()
	check(car.service_repair(), "Workshop repair succeeds")
	var serviced := car.get_telemetry()
	check(serviced["fuel_l"] == fuel_before_service, "Repair does not refill tank")
	check(serviced["deformed_beams"] == 0 and serviced["broken_beams"] == 0, "Repair restores physical structure")
	check(not serviced["running"], "Repair leaves engine off immediately")
	world.step_blocking(0.01)
	world.sync_visuals()
	check(not car.get_telemetry()["running"], "Repair cancels queued starter request")
	world.remove_vehicle(car)
	world.free()
	print("NATIVE SERVICE TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
