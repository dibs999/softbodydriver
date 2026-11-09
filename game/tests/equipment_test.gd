extends SceneTree
var failures := 0

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("Game").selected_map = "proving_grounds"
	root.get_node("Game").settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var scene = current_scene
	scene.world.paused = true
	var v: SBVehicle = scene.player
	var equipment = scene.equipment
	var original := float(v.get_telemetry()["fuel_l"])
	check(v.refuel(5.0) == 0.0, "Running engine rejects fuel")
	v.reset_to(Transform3D(Basis.IDENTITY, equipment.bay))
	scene.world.step_blocking(0.01)
	v.set_input(0, 1, 0, 1)
	v.set_ignition(false)
	scene.world.step_blocking(3.0)
	scene.world.sync_visuals()
	check(equipment.can_refuel(), "Marked service bay permits stationary engine-off fueling")
	var added := v.refuel(1000.0)
	check(added > 0, "Fuel is delivered to real vehicle systems")
	check(absf(float(v.get_telemetry()["fuel_l"]) - float(v.get_info()["fuel_capacity"])) < 0.001, "Fuel stops at tank capacity")
	check(v.refuel(-1.0) == 0.0 and v.refuel(NAN) == 0.0, "Invalid fuel requests rejected")
	check(float(v.get_telemetry()["fuel_l"]) >= original, "Refuel preserves rather than resets tank state")
	for action in ["headlights", "indicator_left", "hazards"]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		check(equipment.handle_action(event), "Equipment input " + action)
	equipment._process(0.0)
	var state: Dictionary = equipment.state_for(v)
	check(state["lights"] and state["headlights"][0].visible, "Headlights project light")
	check(state["hazards"], "Hazards enabled")
	equipment.clock = 0
	equipment._process(0)
	check(state["left"][0].visible and state["right"][0].visible, "Both hazard lamps illuminate")
	equipment.clock = 0.5
	equipment._process(0)
	check(not state["left"][0].visible and not state["right"][0].visible, "Hazard lamps cycle off")
	v.reset_to(Transform3D(Basis.IDENTITY, Vector3(80, 0, 0)))
	scene.world.step_blocking(0.01)
	scene.world.sync_visuals()
	check(not equipment.can_refuel(), "Fuel unavailable away from service bay")
	print("EQUIPMENT TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
