extends SceneTree
const Assist := preload("res://scripts/steering_assist.gd")
var failures := 0

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	if not value: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(is_equal_approx(Assist.apply(1, 0), 1), "Full parking lock remains available")
	check(Assist.limit(200) < Assist.limit(100) and Assist.limit(100) < Assist.limit(50), "Steering demand falls continuously with speed")
	check(Assist.limit(200) < 0.02, "Highway input cannot demand a parking-size wheel angle")
	check(is_equal_approx(Assist.apply(-0.5, -100), -Assist.apply(0.5, 100)), "Reverse and left/right inputs remain symmetric")
	check(Assist.apply(0, 200) == 0, "Releasing steering requests straight wheels")
	var game := root.get_node("Game")
	game.selected_car = "res://cars/concept_gt.car.json"
	game.selected_map = "proving_grounds"
	game.settings["traffic"] = false
	game.settings["steering_assist"] = true
	game.settings["tcs"] = true
	game.settings["abs"] = true
	game.settings["automatic"] = true
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var scene = current_scene
	# Disable background stepping while exercising the active driver controls.
	scene.world.time_scale = 0.0
	scene.world.paused = false
	# Clear flat strip: the default spawn lane contains ramps and crash obstacles.
	scene.player.reset_to(Transform3D(Basis.IDENTITY, Vector3(-200, 0, -195)))
	scene.world.step_blocking(1.0)
	scene.world.sync_visuals()
	Input.action_press("throttle", 1)
	# Stop at highway speed: with realistic driving resistance 12 s of full throttle reach
	# ~200 km/h, more than the flat strip leaves room to brake from.
	for i in 48:
		scene._drive_player(0.25)
		scene.world.step_blocking(0.25)
		scene.world.sync_visuals()
		if scene.player.get_speed_kmh() > 130: break
	Input.action_release("throttle")
	var speed: float = scene.player.get_speed_kmh()
	print("Speed before steering: ", speed)
	check(speed > 100, "Concept reaches highway speed in actual gameplay scene")
	Input.action_press("steer_left", 1)
	scene._drive_player(0.1)
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	var steer: float = scene.player.get_telemetry()["steer"]
	check(steer > 0 and steer < 0.1, "Full keyboard input at speed applies bounded steering through gameplay")
	Input.action_release("steer_left")
	scene._drive_player(0.1)
	scene.world.step_blocking(0.2)
	scene.world.sync_visuals()
	check(absf(float(scene.player.get_telemetry()["steer"])) < 0.001, "Gameplay release recentres steering")
	Input.action_press("steer_right", 1)
	scene._drive_player(0.1)
	scene.world.step_blocking(0.1)
	scene.world.sync_visuals()
	check(float(scene.player.get_telemetry()["steer"]) < 0, "Right input turns in the opposite direction through gameplay")
	Input.action_release("steer_right")
	game.settings["steering_assist"] = false
	Input.action_press("steer_left", 1)
	scene._drive_player(0.1)
	scene.world.step_blocking(0.25)
	scene.world.sync_visuals()
	check(float(scene.player.get_telemetry()["steer"]) > 0.4, "Disabling assist preserves direct expert input")
	Input.action_release("steer_left")
	game.settings["steering_assist"] = true
	Input.action_press("brake", 1)
	for i in 24:
		scene._drive_player(0.25)
		scene.world.step_blocking(0.25)
		scene.world.sync_visuals()
		if scene.player.get_speed_kmh() < 3:
			break
	Input.action_release("brake")
	check(scene.player.get_speed_kmh() < 5, "Gameplay brakes stop the car after the steering maneuver")
	check(scene.player.get_position_ws().is_finite(), "Vehicle remains finite")
	print("STEERING ASSIST TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
