extends SceneTree
## Main-thread cost per system: disables one system at a time and measures the process time.
## godot -s res://tests/perf_breakdown.gd -- <map_id>
var wait := -1
var stage := 0
var samples: Array = []
var scene: Node
var systems: Array = []
var baseline := 0.0

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var game := root.get_node("Game")
	game.selected_map = args[0] if args.size() > 0 else "hill_roads"
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	wait = 0

func _measure() -> float:
	var t := 0.0
	for v in samples: t += v
	return t / maxf(1, samples.size())

func _process(_delta: float) -> bool:
	scene = current_scene
	if wait < 0 or scene == null or not scene.get("player"):
		return false
	if systems.is_empty():
		for name in ["world", "hud", "minimap", "audio", "effects", "equipment", "weather", "wipers", "cam", "road_marks", "mirrors"]:
			var n = scene.get(name)
			if n is Node: systems.append([name, n])
		for c in scene.get_children():
			if c.get_script() and not systems.any(func(e): return e[1] == c):
				systems.append([str(c.name), c])
	wait += 1
	if wait > 40:
		samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if wait == 70:
		var value := _measure()
		if stage == 0:
			baseline = value
			print("baseline process %.1f ms (%d systems)" % [value, systems.size()])
		else:
			var e: Array = systems[stage - 1]
			print("  without %-20s %7.1f ms  (saves %6.1f ms)" % [e[0], value, baseline - value])
			(e[1] as Node).process_mode = Node.PROCESS_MODE_INHERIT
		if stage >= systems.size():
			return true
		var nxt: Array = systems[stage]
		(nxt[1] as Node).process_mode = Node.PROCESS_MODE_DISABLED
		stage += 1
		wait = 20
		samples.clear()
	return false
