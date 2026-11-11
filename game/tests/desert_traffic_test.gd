extends SceneTree
## Desert traffic over the shortcut: a third traffic route leaves the rally loop, crosses the dunes
## on the shortcut and rejoins the loop; a car driven by the traffic AI completes a lap of it
## without rolling over or getting stuck.
## godot --headless -s res://tests/desert_traffic_test.gd
const AIDriver := preload("res://scripts/ai_driver.gd")
const STEP := 0.05
var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "desert"
	game.selected_car = "res://cars/trailhead_4x4.car.json"
	game.settings["traffic"] = false
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

func _run(scene: Node) -> void:
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)
	var routes: Array = scene.map_data.get("ai_routes", [])
	check(routes.size() == 3, "Desert traffic has a route over the shortcut")
	if routes.size() < 3:
		return
	var via: PackedVector3Array = routes[2]["waypoints"]
	var shortcut: PackedVector3Array = scene.map_data["map_paths"][1]
	var player: SBVehicle = scene.player
	player.reset_to(preload("res://scripts/map_builder.gd").car_xform(via[2] + Vector3.UP * 0.4, via[4] - via[2]))
	world.step_blocking(1.0)
	var driver := AIDriver.new(player, via, routes[2]["speeds"], 0.9)
	driver.idx = 2
	var progress := 0
	var prev := driver.idx
	var t := 0.0
	var min_up := 1.0
	var on_shortcut := false
	var mid := shortcut[shortcut.size() / 2]
	while t < 400.0 and progress < via.size() - 4:
		driver.update(STEP)
		world.step_blocking(STEP)
		t += STEP
		var step_idx := posmod(driver.idx - prev, via.size())
		if step_idx < via.size() / 2: progress += step_idx
		prev = driver.idx
		min_up = minf(min_up, player.get_up().y)
		if player.get_position_ws().distance_to(mid) < 12.0: on_shortcut = true
	print("  lap: %d of %d route points in %.0f s, lowest up %.2f" % [progress, via.size(), t, min_up])
	check(on_shortcut and progress >= via.size() - 4, "A traffic car takes the shortcut and completes the lap")
	check(min_up > 0.6, "It stays on its wheels (dunes and jumps included)")
