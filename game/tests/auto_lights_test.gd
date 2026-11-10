extends SceneTree
## Light sensor: dipped beams switch on at night and off in daylight until the driver uses the
## light switch, which then stays in charge.
var failures := 0
var frame := 0
var scene: Node
var phase := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "proving_grounds"
	root.get_node("Game").settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")

func _set_hour(h: float) -> void:
	scene.weather.automatic_time = false
	scene.weather.hour = h
	scene.weather._apply_lighting()

func _lights() -> bool:
	return bool(scene.equipment.state_for(scene.player)["lights"])

func _process(_d: float) -> bool:
	frame += 1
	if scene == null:
		if current_scene and current_scene.get("player"):
			scene = current_scene
			_set_hour(13.0)
			frame = 0
		return false
	if frame < 4: return false
	match phase:
		0:
			check(not _lights(), "Lights off at midday")
			_set_hour(22.5)
			phase = 1; frame = 0
		1:
			check(_lights() and int(scene.equipment.state_for(scene.player)["light_mode"]) == 1, "Dipped beams on at night")
			var ev := InputEventAction.new()
			ev.action = "headlights"
			ev.pressed = true
			scene.equipment.handle_action(ev)   # driver switches to main beam
			_set_hour(13.0)
			phase = 2; frame = 0
		2:
			check(int(scene.equipment.state_for(scene.player)["light_mode"]) == 2 and _lights(), "After a manual switch the sensor no longer overrides the driver")
			print("AUTO LIGHTS TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
