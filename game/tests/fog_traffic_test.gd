extends SceneTree
## Fog: traffic slows down (to ~70 % of its clear-weather pace), and the light sensor turns the
## dipped beams on in the middle of the day.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var clear_top := 0.0
var fog_top := 0.0
var car: SBVehicle

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "autobahn"
	root.get_node("Game").settings["traffic"] = true
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _set_weather(i: int) -> void:
	scene.weather.weather_index = i
	scene.weather._apply_lighting()

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and not current_scene.ai.is_empty():
			scene = current_scene
			scene.weather.automatic_time = false
			scene.weather.hour = 13.0
			_set_weather(0)
			car = scene.ai.keys()[0]
			mark = _sim()
		return false
	match phase:
		0:
			if _sim() - mark > 8.0: clear_top = maxf(clear_top, car.get_speed_kmh())
			if _sim() - mark < 16.0: return false
			_set_weather(scene.weather.FOG)
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark > 10.0: fog_top = maxf(fog_top, car.get_speed_kmh())
			if _sim() - mark < 18.0: return false
			print("  traffic top speed: clear %.0f km/h, fog %.0f km/h" % [clear_top, fog_top])
			check(fog_top < clear_top * 0.85 and fog_top > clear_top * 0.55, "Traffic slows down in fog")
			var lamps: Dictionary = scene.equipment.state_for(scene.player)
			check(bool(lamps["lights"]), "At midday in fog the light sensor turns the dipped beams on")
			phase = 2
		2:
			print("FOG TRAFFIC TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
