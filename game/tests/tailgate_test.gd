extends SceneTree
## Rear lid (estate tailgate, saloon boot lid): physical latch release, struts, repair, refusal
## while driving and on cars without a lid, through the GDExtension.
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
	for path in ["res://cars/meridian_wagon.car.json", "res://cars/meridian_sedan.car.json"]:
		var car := world.spawn_car(path, Transform3D.IDENTITY)
		check(car != null, "%s spawns" % path)
		if car == null:
			continue
		check(bool(car.get_info().get("tailgate_supported", false)), "%s has a physical rear lid" % path)
		car.set_input(0, 1, 0, 1)
		world.step_blocking(1.0)
		world.sync_visuals()
		var broken0 := int(car.get_telemetry()["broken_beams"])
		check(car.release_tailgate(), "Intact rear latch releases")
		check(not car.release_tailgate(), "Repeated release adds nothing")
		world.step_blocking(5.0)
		world.sync_visuals()
		var broken := int(car.get_telemetry()["broken_beams"]) - broken0
		check(car.get_velocity().is_finite() and car.get_speed_kmh() < 1.0, "Car stays at rest with the lid open")
		check(broken == 0, "Opening breaks nothing (got %d)" % broken)
		check(not bool(car.get_lid_states()[1]["latched"]), "Rear latch let go")
		check(car.close_tailgate(), "Open lid can be closed")
		world.step_blocking(5.0)
		world.sync_visuals()
		check(bool(car.get_lid_states()[1]["latched"]), "Closed lid relatches without a repair")
		check(car.release_tailgate(), "Relatched lid opens again")
		world.step_blocking(2.0)
		car.repair_in_place()
		world.step_blocking(0.05)
		world.sync_visuals()
		check(int(car.get_telemetry()["broken_beams"]) == 0 and bool(car.get_lid_states()[1]["latched"]), "Repair shuts and latches the lid")
		car.set_input(1, 0, 0, 0)
		world.step_blocking(4.0)
		world.sync_visuals()
		check(car.get_speed_kmh() > 10 and not car.release_tailgate(), "Release refused while driving (%.1f km/h)" % car.get_speed_kmh())
		world.remove_vehicle(car)
	var hatch := world.spawn_car("res://cars/aurora_sedan.car.json", Transform3D.IDENTITY)
	check(not bool(hatch.get_info().get("tailgate_supported", true)) and not hatch.release_tailgate() and not hatch.close_tailgate(), "Car without a lid refuses")
	world.remove_vehicle(hatch)
	world.free()
	print("TAILGATE TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
