extends SceneTree
var failures := 0
var events: Array[String] = []

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("Game").selected_map = "proving_grounds"
	root.get_node("Game").selected_car = "res://cars/kestrel_hatch.car.json"
	root.get_node("Game").settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var scene = current_scene
	var world: SBWorld = scene.world
	var car: SBVehicle = scene.player
	var equipment = scene.equipment
	world.paused = true
	world.time_scale = 0.0 # No background advancement; tests advance real simulation explicitly.
	scene.set_process(false)
	equipment.set_process(false)
	equipment.service_completed.connect(func(kind: String): events.append(kind))
	car.set_ignition(false)
	car.set_input(0, 1, 0, 1)
	car.puncture_tire(0, 200.0)
	car.break_group("bonnet_latch")
	world.step_blocking(3.0)
	world.sync_visuals()
	var damaged: Dictionary = car.get_telemetry()
	var fuel := float(damaged["fuel_l"])
	check(int(damaged["broken_beams"]) > 0 and damaged["tire_pressure"][0] < 1.0, "Fixture has actual bonnet and tire damage")
	check(equipment.recover_to_service(), "Recovery moves existing vehicle to service")
	var offset: Vector3 = car.get_position_ws() - equipment.bay
	check(Vector2(offset.x, offset.z).length() < 0.2 and absf(offset.y) < 0.8, "Recovery reaches marked bay at vehicle floor height")
	check(int(car.get_telemetry()["broken_beams"]) == int(damaged["broken_beams"]), "Recovery preserves broken structure")
	check(car.get_telemetry()["tire_pressure"][0] < 1.0 and absf(float(car.get_telemetry()["fuel_l"]) - fuel) < 0.001, "Recovery preserves tire damage and fuel")
	check(car.get_velocity().length() < 0.01, "Tow stops vehicle velocity")
	events.clear()
	world.paused = false
	Input.action_press("service_repair")
	equipment._process(100.0)
	check(equipment.service_progress == 0.0, "Wall time alone cannot advance service")
	# Drive the same service state machine with measured physics time.
	world.step_blocking(1.0)
	world.sync_visuals()
	# Recover again only to eliminate suspension settling velocity; no state reset.
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	equipment._process(0.0)
	check(absf(equipment.service_progress - 0.25) < 0.001, "One physical second advances four-second repair by quarter")
	world.paused = true
	equipment._process(0.0)
	check(equipment.service_progress == 0.0, "Pause cancels unfinished repair")
	world.paused = false
	equipment.update_service(1.0, true, false)
	equipment.update_service(0.0, false, false)
	check(equipment.service_progress == 0.0, "Releasing repair key cancels progress")
	equipment.update_service(1.0, true, false)
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay + Vector3(20, 0, 0)))
	equipment.update_service(1.0, true, false)
	check(equipment.service_progress == 0.0 and events.is_empty(), "Leaving bay cancels without completing repair")
	equipment.recover_to_service()
	events.clear()
	equipment.update_service(3.9, true, false)
	check(events.is_empty() and car.get_telemetry()["tire_pressure"][0] < 1.0, "Partial repair does not restore damage early")
	equipment.update_service(0.1, true, false)
	check(events == ["repair"], "Full hold emits exactly one repair completion")
	check(int(car.get_telemetry()["broken_beams"]) == 0 and car.get_telemetry()["tire_pressure"][0] > 25, "Service repairs structure and tire pressure")
	check(absf(float(car.get_telemetry()["fuel_l"]) - fuel) < 0.001 and not car.get_telemetry()["running"], "Repair preserves fuel and keeps engine off")
	equipment.update_service(10.0, true, false)
	check(events == ["repair"], "Holding key after completion cannot repeat repair")
	equipment.update_service(0.0, false, false)
	equipment.update_service(2.0, false, true)
	check(absf(equipment.refuel_delivered_litres - 1.6) < 0.001, "Fuel display tracks actual liters delivered")
	check(absf(float(car.get_telemetry()["fuel_l"]) - fuel - 1.6) < 0.001, "Refueling updates physical tank")
	check(events == ["repair", "refuel"], "Real fuel delivery completes service objective once")
	equipment.update_service(1.0, false, true)
	check(events == ["repair", "refuel"], "Continuous fueling does not repeat completion signal")
	equipment.update_service(1.0, true, false)
	var other: SBVehicle = world.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D(Basis.IDENTITY, equipment.bay))
	other.set_ignition(false)
	world.step_blocking(0.01)
	world.sync_visuals()
	other.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	scene.player = other
	equipment.update_service(2.0, true, false)
	check(equipment.service_progress == 0.0, "Changing vehicle cancels progress without transferring work")
	scene.player = car
	world.remove_vehicle(other)
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay))
	equipment.update_service(0.0, false, false)
	equipment.update_service(1.0, true, false)
	car.relocate_to(Transform3D(Basis.IDENTITY, equipment.bay + Vector3(0, 1.0, 0)))
	world.step_blocking(0.2)
	world.sync_visuals()
	check(car.get_velocity().length() > 0.25, "Moving fixture exceeds stationary service threshold")
	equipment.update_service(1.0, true, false)
	check(equipment.service_progress == 0.0, "Moving within bay cancels repair")
	Input.action_release("service_repair")
	world.paused = true
	print("SERVICE TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
