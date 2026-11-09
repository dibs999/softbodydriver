extends SceneTree
const Instruments := preload("res://scripts/instrument_cluster.gd")
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
	game.world.paused = true
	game.world.step_blocking(1.0)
	game.world.sync_visuals()
	var car: SBVehicle = game.player
	var camera = game.cam
	camera.equipment = game.equipment
	camera.mode = camera.Mode.COCKPIT
	camera._update_dashboard(0.1)
	var cluster: Control = camera._instruments
	var t := car.get_telemetry()
	check(camera._dashboard.visible, "Cockpit opens actual in-dash instruments")
	check(absf(cluster.readings["fuel"] - float(t["fuel_l"])) < 0.001 and absf(cluster.readings["coolant"] - float(t["coolant_temp"])) < 0.001, "Embedded fuel and coolant follow native telemetry")
	var event := InputEventAction.new()
	event.pressed = true
	event.action = "headlights"
	game.equipment.handle_action(event)
	game.equipment.handle_action(event)
	event.action = "hazards"
	game.equipment.handle_action(event)
	game.equipment.clock = 0.1
	camera._update_dashboard(0.1)
	check(cluster.readings["light_mode"] == 2, "Dashboard reflects actual high beam mode")
	check(cluster.readings["left"] and cluster.readings["right"], "Both cockpit hazard indicators illuminate in phase")
	game.equipment.clock = 0.6
	camera._update_dashboard(0.1)
	check(not cluster.readings["left"] and not cluster.readings["right"], "Cockpit indicators share exterior off phase")
	car.set_ignition(false)
	game.world.step_blocking(0.1)
	game.world.sync_visuals()
	camera._update_dashboard(0.1)
	check(cluster.readings["warning"]["text"] == "MOTOR AUS", "Actual engine-off warning remains visible inside cockpit")
	check(car.set_door_open(0, true), "Native door command releases driver latch")
	camera._update_dashboard(0.1)
	check(cluster.readings["warning"]["text"] == "TÜR OFFEN", "Cockpit shows actual unlocked door ahead of benign engine-off label")
	check(camera._center_display.warning["text"] == "TÜR OFFEN", "Center display shares physical door warning")
	car.service_repair()
	camera._update_dashboard(0.1)
	check(cluster.readings["warning"]["text"] == "MOTOR AUS", "Repair restores closed door warning state")
	car.puncture_tire(0, 200)
	game.world.step_blocking(1.0)
	game.world.sync_visuals()
	camera._update_dashboard(0.1)
	check(cluster.readings["warning"]["text"] == "REIFENDRUCK", "Actual tire pressure loss overrides benign engine-off label")
	check(camera._center_display.warning["text"] == "REIFENDRUCK", "Center display uses same actual priority warning")
	car.set_tcs(false)
	car.set_abs(false)
	car.set_automatic(false)
	camera._update_dashboard(0.1)
	check(not cluster.readings["tcs"] and not cluster.readings["abs"] and not cluster.readings["automatic"], "Cockpit reads actual driver aid and gearbox switches")
	var synthetic := t.duplicate()
	synthetic["seized"] = true
	synthetic["fuel_l"] = 0
	check(Instruments.warning_for(synthetic, car.get_info())["text"] == "MOTOR FEST", "Seized engine has priority over low fuel")
	camera.mode = camera.Mode.CHASE
	camera._update_dashboard(1.0)
	check(not camera._dashboard.visible and camera._instrument_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and camera._center_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Exterior cameras do not schedule dashboard viewport rendering")
	if game.audio: game.audio.free()
	game.queue_free()
	await process_frame
	print("COCKPIT INSTRUMENTS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
