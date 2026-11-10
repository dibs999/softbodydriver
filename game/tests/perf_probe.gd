extends SceneTree
## Rendering / CPU cost per map: godot -s res://tests/perf_probe.gd [-- <map_id> ...]
## Prints draw calls, visible objects, primitives, process time, physics load and extra viewports.
var maps: Array = []
var wait := -1
var samples: Array = []
var current := ""

func _initialize() -> void:
	call_deferred("_next")

func _next() -> void:
	if maps.is_empty() and current == "":
		var args := OS.get_cmdline_user_args()
		for m in root.get_node("Game").MAPS:
			if args.is_empty() or m["id"] in args:
				maps.append(m["id"])
	if maps.is_empty():
		quit()
		return
	current = maps.pop_front()
	var game := root.get_node("Game")
	if OS.has_environment("PRESET"):
		# Measure with the preset without saving it into the player's profile.
		game.settings_config_path = "user://perf_probe_%d.cfg" % OS.get_process_id()
		game._set_graphics_preset(int(OS.get_environment("PRESET")))
	game.selected_map = current
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	wait = 0
	samples.clear()

func _count(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count(c, cls)
	return n

func _process(delta: float) -> bool:
	var scene := current_scene
	if wait < 0 or scene == null or not scene.get("player"):
		return false
	wait += 1
	if wait > 60 and wait <= 90:
		samples.append([RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	if wait == 91:
		var s := [0.0, 0.0, 0.0, 0.0]
		for row in samples:
			for k in 4: s[k] += row[k] / samples.size()
		var stats: Dictionary = scene.world.get_stats()
		print("%-16s draws %5d  objects %5d  prims %8.0fk  process %5.1f ms  realtime %.2f  nodes %d  mmi %d  viewports %d  lights %d  cars %d" % [
			current, s[0], s[1], s[2] / 1000.0, s[3], float(stats.get("realtime_factor", 0)), scene.get_tree().get_node_count(),
			_count(scene, "MultiMeshInstance3D"), _count(scene, "SubViewport"), _count(scene, "Light3D"), scene.vehicles.size()])
		wait = -1
		call_deferred("_next")
	return false
