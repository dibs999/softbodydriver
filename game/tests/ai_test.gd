extends SceneTree
## Lets the AI traffic drive for a while and reports progress: godot --headless -s res://tests/ai_test.gd -- [map]

var frame := 0
var t0 := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		var args := OS.get_cmdline_user_args()
		root.get_node("Game").selected_map = args[0] if args.size() > 0 else "proving_grounds"
		change_scene_to_file("res://scenes/game.tscn")
		t0 = Time.get_ticks_msec()
	if frame > 5 and (Time.get_ticks_msec() - t0) % 10000 < 20:
		var g = current_scene
		for v in g.ai.keys():
			var t: Dictionary = v.get_telemetry()
			print("%5.1fs %-26s wp %3d  %5.1f km/h  pos %s  status '%s' dmg %.2f" % [(Time.get_ticks_msec() - t0) / 1000.0, v.get_info()["name"], g.ai[v].idx, t["speed_kmh"], v.get_position_ws().round(), t["status"], t["zones"][0]])
	return Time.get_ticks_msec() - t0 > 62000
