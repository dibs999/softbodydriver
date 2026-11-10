extends SceneTree
## Race (Rennen): two AI opponents line up ahead of the player, stay on the grid during the
## countdown, then drive the lap through the same gates; the player gets a place at the finish
## and the opponents leave the map again.
## godot --headless -s res://tests/race_test.gd
const AIDriver := preload("res://scripts/ai_driver.gd")
const STEP := 0.05

var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	# Optional: -- <map> [traffic] to try other maps.
	var args := OS.get_cmdline_user_args()
	game.selected_map = args[0] if args.size() > 0 else "proving_grounds"
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.settings["traffic"] = args.size() > 1 and args[1] == "traffic"
	game.settings["show_help"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return frame > 600
	if frame < 5:
		return false
	_run(scene)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true

func _step(scene: Node, activity: Node, player_ai: Variant) -> void:
	for v in scene.ai.keys():
		scene.ai[v].update(STEP)
	if player_ai != null:
		player_ai.update(STEP)
	scene.world.step_blocking(STEP)
	activity._process(STEP)

func _run(scene: Node) -> void:
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)
	var activity: Node = scene.activity
	activity.set_process(false)
	# Keep the player's real records untouched.
	activity.records_path = "user://race_test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activity.records_path))
	check(4 in activity.available_modes(), "Race is offered on the map")
	var base_vehicles: int = scene.vehicles.size()
	var base_ai: int = scene.ai.size()
	activity.mode = 4
	activity.start()
	for i in 40:
		_step(scene, activity, null)
		if not activity._arming: break
	var opponents: Array = activity.opponents()
	check(opponents.size() == 2 and scene.vehicles.size() == base_vehicles + 2 and scene.ai.size() == base_ai + 2, "Two opponents join the race")
	var grid: Array[Vector3] = []
	for v in opponents: grid.append(v.get_position_ws())
	var player_start: Vector3 = scene.player.get_position_ws()
	var ahead := true
	for p in grid:
		ahead = ahead and (p - player_start).dot(scene.player.get_forward()) > 4.0
	check(ahead, "The opponents start one row ahead of the player")
	# Countdown: nobody moves.
	var t := 0.0
	while activity.countdown > 0.0 and t < 6.0:
		_step(scene, activity, null)
		t += STEP
	var still := true
	for i in opponents.size():
		still = still and opponents[i].get_position_ws().distance_to(grid[i]) < 1.0
	check(still, "Opponents wait on the grid during the countdown")
	# Race: the player is driven by the same AI, slower than the opponents.
	var player_ai := AIDriver.new(scene.player, scene.map_data["waypoints"], scene.map_data["speeds"], 0.8)
	t = 0.0
	var moved := false
	while activity.active and t < 400.0:
		_step(scene, activity, player_ai)
		t += STEP
		if not moved and t > 5.0:
			moved = opponents.all(func(v): return v.get_position_ws().distance_to(grid[opponents.find(v)]) > 20.0)
	check(moved, "Opponents drive off after the start")
	var result: Dictionary = activity.last_result
	print("  place %s of %s in %.1f s, %d checkpoints" % [result.get("place"), result.get("field"), float(result.get("elapsed", 0.0)), int(result.get("checkpoints", 0))])
	check(result.get("mode", -1) == 4 and result.get("checkpoints", 0) > 10, "The player completes the race lap")
	check(int(result.get("place", 0)) >= 1 and int(result.get("place", 0)) <= 3, "The player gets a place (1-3)")
	check(int(result.get("place", 0)) > 1, "Faster opponents finish ahead of a slow player")
	for i in 5: _step(scene, activity, null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activity.records_path))
	check(scene.vehicles.size() == base_vehicles and scene.ai.size() == base_ai and opponents.all(func(v): return not is_instance_valid(v) or v.is_queued_for_deletion()), "Opponents leave after the race")
