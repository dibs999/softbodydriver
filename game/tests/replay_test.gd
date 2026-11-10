extends SceneTree
## Replay (F5): the player's recent motion is recorded, replay shows recorded frames (the start as
## frame 0, the latest as the last frame) with physics paused, and ending it returns to the live car.
## godot --headless -s res://tests/replay_test.gd

var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.settings["traffic"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return frame > 600
	if frame < 10:
		return false
	scene.set_process(false)
	var car: SBVehicle = scene.player
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	world.sync_visuals()
	var start := car.get_position_ws()
	for i in 150:
		car.set_input(0.7, 0, 0, 0)
		world.step_blocking(0.02)
		world.sync_visuals()
	var live := car.get_position_ws()
	print("  drove %.1f m" % start.distance_to(live))
	scene.toggle_replay()
	var frames: int = scene._replay_frames
	check(frames >= 60 and world.paused, "Replay starts with recorded frames and paused physics")
	car.replay_show(0)
	world.sync_visuals()
	var first := car.get_position_ws()
	car.replay_show(frames - 1)
	world.sync_visuals()
	var last := car.get_position_ws()
	print("  frame 0 %.2f m from the start, last frame %.2f m from the live car" % [first.distance_to(start), last.distance_to(live)])
	check(first.distance_to(start) < 1.0 and last.distance_to(live) < 1.0 and first.distance_to(last) > 5.0,
		"Replay frames show the recorded motion from start to now")
	scene.toggle_replay()
	world.sync_visuals()
	check(car.get_position_ws().distance_to(live) < 0.5 and scene._replay_frames == 0, "Ending the replay returns to the live car")
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
