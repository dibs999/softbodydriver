extends SceneTree
## Quitting from a running map (engine sound playing) shuts down cleanly through Game.quit_cleanly:
## every audio player is stopped and released before the engine quits.
## godot --headless -s res://tests/quit_test.gd
var frame := 0
var asked := false

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if frame > 900:
		print("TEST FAILED (never quit)")
		quit(1)
		return true
	if scene == null or not scene.get("player") or frame < 30 or asked: return false
	var players: Array[Node] = root.find_children("*", "AudioStreamPlayer", true, false)
	var playing := players.filter(func(p: Node) -> bool: return (p as AudioStreamPlayer).playing)
	print("audio players: %d, playing: %d" % [players.size(), playing.size()])
	asked = true
	root.get_node("Game").quit_cleanly()
	# quit_cleanly() stops the players at once and quits a few frames later.
	var still := players.filter(func(p: Node) -> bool: return is_instance_valid(p) and (p as AudioStreamPlayer).playing)
	print("Audio stopped before the quit: ", still.is_empty())
	print("TEST OK" if still.is_empty() and playing.size() > 0 else "TEST FAILED")
	return false
