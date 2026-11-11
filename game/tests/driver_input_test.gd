extends SceneTree
var failures := 0
func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var state := root.get_node("Game")
	var saved_path: String = state.settings_config_path
	var path := "user://driver_input_%s.cfg" % ("%d_%d" % [Time.get_ticks_usec(), randi()])
	state.settings_config_path = path
	state.settings["traffic"] = false
	state.settings["automatic"] = true
	state.settings["tcs"] = true
	state.settings["abs"] = true
	state.selected_map = "proving_grounds"
	state.selected_car = "res://cars/kestrel_hatch.car.json"
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	var scene = current_scene
	scene.set_process(false)
	var world: SBWorld = scene.world
	world.time_scale = 0.0 # Freeze background stepping while retaining real active driving controls.
	world.paused = false
	var car: SBVehicle = scene.player
	car.set_automatic(true)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(-110, 0, -5)))
	world.step_blocking(1)
	car.set_gear(-1)
	car.set_input(1, 0, 0, 0)
	world.step_blocking(3)
	world.sync_visuals()
	var reverse := car.get_telemetry()
	check(reverse["gear"] == -1 and reverse["speed_kmh"] > 10 and car.get_velocity().dot(car.get_forward()) < 0, "Fixture actually travels backward at speed")
	Input.action_press("throttle")
	scene._drive_player(0.5)
	world.step_blocking(0.02)
	world.sync_visuals()
	var braking := car.get_telemetry()
	check(braking["gear"] == -1 and braking["brake"] > 0.9 and braking["throttle"] < 0.1, "Forward trigger brakes fast reverse without selecting drive")
	car.relocate_to(Transform3D(Basis.IDENTITY, Vector3(-110, 0, -5)))
	scene._drive_player(0.21)
	world.step_blocking(0.5)
	world.sync_visuals()
	check(car.get_telemetry()["gear"] == 1, "Forward hold changes direction only after stopping")
	car.set_automatic(false)
	Input.action_press("clutch")
	scene._drive_player(0.02)
	world.step_blocking(0.2)
	world.sync_visuals()
	check(car.get_telemetry()["clutch"] < 0.01, "Manual clutch input disengages physical drivetrain")
	Input.action_release("clutch")
	var toggle := InputEventAction.new()
	toggle.action = "toggle_gearbox"
	toggle.pressed = true
	scene._unhandled_input(toggle)
	# An automatic shift temporarily opens the clutch. Observe the whole launch,
	# rather than treating a single snapshot during a valid shift as a stuck pedal.
	var observed_engagement := 0.0
	for frame in 10:
		scene._drive_player(0.1)
		world.step_blocking(0.1)
		world.sync_visuals()
		observed_engagement = maxf(observed_engagement, float(car.get_telemetry()["clutch"]))
	var result := car.get_telemetry()
	check(car.is_automatic(), "Automatic toggle changes native gearbox mode")
	check(observed_engagement > 0.1, "Automatic mode re-engages clutch after manual override")
	check(car.get_speed_kmh() > 1, "Automatic drivetrain accelerates after clutch handoff")
	if observed_engagement <= 0.1 or car.get_speed_kmh() <= 1:
		print("peak clutch engagement = ", observed_engagement)
		for key in ["gear", "rpm", "clutch", "speed_kmh", "running", "status", "throttle", "brake", "clutch_wear", "gearbox_damage", "broken_beams", "shift_remaining"]:
			print("handoff ", key, " = ", result.get(key))
	Input.action_release("throttle")
	state.settings_config_path = saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("DRIVER INPUT TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
