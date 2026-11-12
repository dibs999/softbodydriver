extends SceneTree
## Slow-PC hint: with the physics below 85 % of real time for 8 s the game says once that
## switching traffic off relieves the CPU; short dips and healthy physics say nothing.
## godot --headless -s res://tests/physics_load_hint_test.gd
var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player") or scene.get("_loading_overlay"):
		return frame > 20000
	var shown := false
	# Healthy physics: never.
	for i in 400: shown = shown or scene.check_physics_load(0.05, 0.98)
	check(not shown, "No hint while the physics keeps real time")
	# A 5 s dip (a crash with many parts) recovers: no hint.
	for i in 100: shown = shown or scene.check_physics_load(0.05, 0.6)
	for i in 200: shown = shown or scene.check_physics_load(0.05, 1.0)
	check(not shown, "No hint for a short dip")
	# Sustained 52 %: the hint comes after ~8 s, once.
	var at := -1
	for i in 300:
		if scene.check_physics_load(0.05, 0.52) and at < 0: at = i
	check(at >= 150 and at <= 175, "Hint after about 8 s at 52 %% (step %d)" % at)
	var again := false
	for i in 400: again = again or scene.check_physics_load(0.05, 0.4)
	check(not again, "The hint is given only once")
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
