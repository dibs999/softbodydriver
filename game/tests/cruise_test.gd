extends SceneTree
## Cruise control: V at speed holds it within a few km/h, more throttle overtakes and the speed
## comes back, the brake switches it off; below 30 km/h it does not engage.
## godot --headless -s res://tests/cruise_test.gd
var scene: Node
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	call_deferred("run")

func tick(n: int) -> void:
	for i in n:
		scene._drive_player(0.05)
		scene.world.step_blocking(0.05)
		scene.world.sync_visuals()

func kmh() -> float:
	return scene.player.get_speed_kmh()

func run() -> void:
	var game := root.get_node("Game")
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.selected_map = "autobahn"
	game.settings["traffic"] = false
	game.settings["automatic"] = true
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	scene = current_scene
	scene.set_process(false)
	scene.world.paused = false
	scene.world.time_scale = 0.0
	scene.world.step_blocking(1.0)
	scene.player.start_engine()
	tick(20)
	check(not scene.set_cruise(true), "Below 30 km/h cruise control does not engage")
	Input.action_press("throttle")
	for i in 400:
		tick(1)
		if kmh() >= 90.0: break
	Input.action_release("throttle")
	check(scene.set_cruise(true), "At speed it engages")
	var target: float = scene.cruise_kmh
	tick(300)   # 15 s
	var lo := INF
	var hi := -INF
	for i in 100:
		tick(1)
		lo = minf(lo, kmh())
		hi = maxf(hi, kmh())
	print("  target %.0f km/h, held %.1f .. %.1f km/h" % [target, lo, hi])
	check(lo > target - 3.0 and hi < target + 3.0, "It holds the set speed within 3 km/h")
	Input.action_press("throttle")
	tick(80)
	Input.action_release("throttle")
	var overtake := kmh()
	print("  overtaking: %.1f km/h" % overtake)
	check(overtake > target + 8.0 and scene.cruise_kmh == target, "More throttle overtakes and keeps the setting")
	tick(400)
	print("  after overtaking: %.1f km/h" % kmh())
	check(absf(kmh() - target) < 3.0, "and the speed comes back to the set one")
	Input.action_press("brake")
	tick(4)
	Input.action_release("brake")
	check(scene.cruise_kmh < 0.0, "The brake switches it off")
	var before := kmh()
	tick(100)
	print("  coasting: %.1f -> %.1f km/h" % [before, kmh()])
	check(kmh() < before - 3.0, "and the car then coasts")
	if failed or OS.has_environment("CRUISE_DIAG"):
		# A rare suite-only failure (car at ~0 km/h after engaging at 90): say where and in what state.
		var t: Dictionary = scene.player.get_telemetry()
		print("  diagnostics: map %s car %s at %s, running %s, gear %s, rpm %.0f, status %s, broken beams %s" % [game.selected_map,
			scene.player.get_info().get("id", "?"), scene.player.get_position_ws(), t.get("running"), t.get("gear"),
			float(t.get("rpm", 0.0)), t.get("status", ""), t.get("broken_beams")])
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
