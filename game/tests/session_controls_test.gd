extends SceneTree
## Exercise the controller-accessible pause menu and non-destructive recovery.
var failures := 0
var scene: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	if not value: failures += 1

func button(caption: String) -> Button:
	for node in scene.pause_menu.find_children("*", "Button", true, false):
		if node.text == caption: return node
	return null

func run() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	scene = current_scene
	scene.set_process(false)
	scene.world.time_scale = 0.0
	scene.world.step_blocking(1.0)
	scene.world.sync_visuals()
	scene._reverse_hold = 0.3
	scene._toggle_pause()
	check(scene.world.paused and scene._reverse_hold == 0, "Opening pause clears pending direction change")
	scene._pause_activity.select(1)
	scene._pause_activity.item_selected.emit(1)
	check(scene.activity.mode == 1 and not scene.activity.active, "Pause activity picker prepares a time trial")
	scene._pause_weather.select(2)
	scene._pause_weather.item_selected.emit(2)
	scene._pause_time.select(2)
	scene._pause_time.item_selected.emit(2)
	check(scene.weather.weather_index == 2 and scene.weather.hour == 0 and scene.weather._rain.emitting, "Pause controls enable rain and night without function keys")
	scene._pause_clock.button_pressed = true
	check(scene.weather.automatic_time, "Automatic day-night checkbox controls actual weather clock")
	var start := button("Auswahl starten / laufenden Versuch abbrechen")
	check(start != null, "Activity start is focusable through a real menu button")
	if start: start.pressed.emit()
	check(scene.activity.active and not scene.pause_menu.visible and not scene.world.paused, "Activity menu starts a run and resumes simulation")
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	scene._toggle_pause()
	if start: start.pressed.emit()
	check(not scene.activity.active, "Same menu button cancels running activity")
	scene.player.service_repair()
	scene._toggle_pause()
	var driver_door := button("Fahrertür öffnen / schließen")
	var passenger_door := button("Beifahrertür öffnen / schließen")
	check(driver_door != null and passenger_door != null, "Both door controls are reachable as focusable pause menu buttons")
	if driver_door: driver_door.pressed.emit()
	var doors: Array = scene.player.get_door_states()
	check(doors.size() == 2 and bool(doors[0].requested_open) and not bool(doors[1].requested_open) and not scene.pause_menu.visible,
		"Driver menu command releases only driver door and resumes game")
	scene._toggle_pause()
	if passenger_door: passenger_door.pressed.emit()
	doors = scene.player.get_door_states()
	check(doors.size() == 2 and bool(doors[1].requested_open) and not scene.world.paused, "Passenger menu command releases passenger door and resumes game")
	scene.player.service_repair()
	scene.player.set_input(0, 1, 0, 1)
	scene.world.step_blocking(0.5)
	scene.world.sync_visuals()
	scene.player.release_bonnet()
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	var damage := int(scene.player.get_telemetry()["broken_beams"])
	var fuel := float(scene.player.get_telemetry()["fuel_l"])
	scene.player.relocate_to(Transform3D(Basis.IDENTITY, Vector3(20, -40, 0)))
	scene._process(0.01)
	check(scene.player.get_position_ws().distance_to(scene.equipment.bay) < 2.0, "Leaving world bounds recovers vehicle to reachable service")
	check(damage >= 6 and int(scene.player.get_telemetry()["broken_beams"]) == damage and absf(float(scene.player.get_telemetry()["fuel_l"]) - fuel) < 0.001,
		"Automatic recovery preserves physical damage and fuel")
	scene.world.paused = true
	scene._reverse_hold = 0.3
	Input.action_press("brake")
	scene._drive_player(1.0)
	Input.action_release("brake")
	check(scene._reverse_hold == 0.0, "Physics pause cannot accumulate reverse hold")
	if scene.audio: scene.audio.free()
	scene.queue_free()
	await process_frame
	print("SESSION CONTROLS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
