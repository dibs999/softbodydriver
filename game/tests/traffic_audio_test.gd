extends SceneTree
## Other cars are heard: the nearest traffic car gets a 3D engine and tyre voice that runs while it
## drives, at most four cars have one, cars out of earshot have none, and a physics pause pauses it.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var car: SBVehicle

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "hill_roads"
	root.get_node("Game").settings["traffic"] = true
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("traffic_audio") and not current_scene.ai.is_empty():
			scene = current_scene
			mark = _sim()
		return false
	var ta = scene.traffic_audio
	match phase:
		0:
			if _sim() - mark < 4.0: return false
			car = scene.ai.keys()[0]
			# Park the player 12 m beside that traffic car: the camera (the listener) follows.
			var f := Vector3(1, 0, 0)
			var spot: Vector3 = car.get_position_ws() + car.get_right() * 12.0
			scene.player.relocate_to(Transform3D(Basis(f, Vector3.UP, f.cross(Vector3.UP)), spot))
			scene.cam.snap()
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 1.5: return false
			check(ta.emitters.has(car), "The nearby traffic car has a voice")
			check(ta.engine_level(car) > 0.05, "Its engine is heard (level %.2f)" % ta.engine_level(car))
			var e: Dictionary = ta.emitters.get(car, {})
			var playing := 0
			for p in e.get("engine", []):
				if p.playing: playing += 1
			check(playing >= 3 and e.get("road") and e["road"].playing, "Engine loops and tyre roar play (%d loops)" % playing)
			check(ta.emitters.size() <= ta.MAX_CARS, "At most %d cars have a voice (%d)" % [ta.MAX_CARS, ta.emitters.size()])
			var ear: Vector3 = scene.cam.global_position
			var far_ok := true
			for v in ta.emitters:
				if v.get_position_ws().distance_to(ear) > ta.RANGE + 20.0: far_ok = false
			check(far_ok, "No voice beyond earshot")
			check(not ta.emitters.has(scene.player), "The player's own car is not doubled")
			scene.world.paused = true
			phase = 2
		2:
			var e: Dictionary = ta.emitters.get(car, {})
			check(not e.is_empty() and e["engine"][0].stream_paused and e["road"].stream_paused, "A physics pause pauses the traffic sound")
			scene.world.paused = false
			phase = 3
		3:
			print("TRAFFIC AUDIO TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
