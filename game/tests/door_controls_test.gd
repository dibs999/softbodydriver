extends SceneTree
var failures := 0
func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var state := root.get_node("Game")
	state.settings["traffic"] = false
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var game = current_scene
	game.set_process(false)
	var world: SBWorld = game.world
	world.paused = true
	var car: SBVehicle = game.player
	car.set_input(0, 1, 0, 1)
	car.set_ignition(false)
	world.step_blocking(2)
	world.sync_visuals()
	var doors := car.get_door_states()
	check(doors.size() == 2, "Reference car exposes two physical front doors")
	if doors.size() != 2:
		if game.audio: game.audio.free()
		game.queue_free()
		await process_frame
		quit(1)
		return
	check(doors[0]["latched"] and doors[1]["latched"] and not doors[0]["open"], "Both doors start closed and latched")
	# The bonnet uses a separate hydro channel and intentionally broken latch.
	# Door closing must not silently repair that existing mechanical state.
	check(car.release_bonnet(), "Bonnet remains independently operable alongside doors")
	world.step_blocking(3)
	world.sync_visuals()
	var broken := int(car.get_telemetry()["broken_beams"])
	check(broken > 0, "Fixture contains existing broken bonnet latch beams")
	var fuel := float(car.get_telemetry()["fuel_l"])
	var key := InputEventKey.new()
	key.physical_keycode = KEY_U
	key.pressed = true
	check(game.equipment.handle_action(key), "Unmodified U is a driver-door action")
	world.sync_visuals()
	doors = car.get_door_states()
	check(doors[0]["requested_open"] and not doors[1]["requested_open"], "Driver action does not open passenger door")
	check(not doors[0]["latched"] and int(car.get_telemetry()["broken_beams"]) == broken, "Manual unlatching does not create broken beams")
	world.step_blocking(4)
	world.sync_visuals()
	doors = car.get_door_states()
	check(doors[0]["angle_degrees"] > 20 and doors[0]["attached"], "Door physically swings open on attached hinges")
	check(int(car.get_telemetry()["broken_beams"]) == broken, "Normal door opening preserves attachment structure")
	check(game.equipment.toggle_door(0), "Same interaction requests closure")
	world.step_blocking(8)
	world.sync_visuals()
	doors = car.get_door_states()
	check(doors[0]["latched"] and doors[0]["angle_degrees"] < 3 and not doors[0]["requested_open"], "Door physically closes and relatches")
	check(absf(float(car.get_telemetry()["fuel_l"]) - fuel) < 0.001, "Door operation does not refill fuel")
	check(int(car.get_telemetry()["broken_beams"]) == broken, "Closing door preserves pre-existing broken latch beams")
	key.shift_pressed = true
	check(game.equipment.handle_action(key), "Shift+U is a passenger-door action")
	doors = car.get_door_states()
	check(doors[1]["requested_open"] and not doors[0]["requested_open"], "Shift modifier opens only passenger door")
	world.step_blocking(3)
	world.sync_visuals()
	check(car.service_repair(), "Service can restore an open car")
	doors = car.get_door_states()
	check(doors[0]["latched"] and doors[1]["latched"] and not doors[0]["requested_open"] and not doors[1]["requested_open"] and doors[1]["travel"] == 0.0, "Repair clears door requests, actuator stroke and latches")
	car.relocate_to(Transform3D(Basis.IDENTITY, Vector3(-100, 1.0, -5)))
	world.step_blocking(0.2)
	world.sync_visuals()
	check(car.get_speed_kmh() > 2.0, "Moving fixture has measurable native velocity")
	check(not car.set_door_open(0, true), "Native API rejects door opening while moving")
	check(not car.set_door_open(-1, true) and not car.toggle_door(2), "Invalid door indices are rejected")
	if game.audio: game.audio.free()
	game.queue_free()
	await process_frame
	print("DOOR CONTROLS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
