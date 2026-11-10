extends SceneTree
## Crash test activity on the proving ground: run-up, impact with the wall, report and stars.
var failures := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(DrivingActivity_stars(56.0, 35.0, 0.5, 0.0) == 5, "A crumple zone that soaks up the pulse earns five stars")
	check(DrivingActivity_stars(56.0, 95.0, 0.1, 0.4) == 1, "A rigid front and a crushed cabin earn one star")
	check(DrivingActivity_stars(30.0, 20.0, 0.3, 0.0) == 0, "Below the test speed there is no rating")
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var scene := current_scene
	var activity = scene.activity
	activity.records_path = "user://crash_test_activity_test.cfg"
	check(5 in activity.available_modes(), "Crash test is offered on the proving ground")
	activity.mode = 5
	activity.start()
	var car: SBVehicle = scene.player
	scene.world.paused = false
	var t := 0.0
	var t0 := float(scene.world.get_stats()["sim_time"])
	var last_print := -1
	while t < 45.0 and activity.last_result.is_empty():
		await process_frame
		t = float(scene.world.get_stats()["sim_time"]) - t0
		if int(t) != last_print and int(t) % 5 == 0:
			last_print = int(t)
			print("  t=%.0f %s" % [t, activity.message])
		if activity.countdown <= 0.0 and not activity._arming:
			# Hold ~60 km/h down the crash lane, straight at the wall.
			var v := absf(car.get_speed_kmh())
			if v < 62.0: Input.action_press("throttle")
			else: Input.action_release("throttle")
	Input.action_release("throttle")
	scene.world.paused = true
	var r: Dictionary = activity.last_result
	print("result ", r)
	check(r.get("mode", 0) == 5, "The run ends with a crash test result")
	var crash: Dictionary = r.get("crash", {})
	check(float(crash.get("speed", 0.0)) >= 50.0 and float(crash.get("speed", 0.0)) < 75.0, "Impact speed is measured (%.0f km/h)" % float(crash.get("speed", 0.0)))
	check(float(crash.get("peak_g", 0.0)) > 8.0, "Peak deceleration is measured (%.0f g)" % float(crash.get("peak_g", 0.0)))
	check(float(crash.get("front", 0.0)) > 0.1, "The front took the hit")
	check(int(crash.get("stars", 0)) >= 1 and int(crash.get("stars", 0)) <= 5, "Stars are awarded")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://crash_test_activity_test.cfg"))
	if scene.audio: scene.audio.free()
	for player in scene.find_children("*", "AudioStreamPlayer", true, false):
		(player as AudioStreamPlayer).stop()
		player.free()
	scene.queue_free()
	await process_frame
	await process_frame
	print("CRASH TEST ACTIVITY TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)

static func DrivingActivity_stars(speed: float, g: float, front: float, cabin: float) -> int:
	return preload("res://scripts/driving_activity.gd").crash_stars(speed, g, front, cabin)
