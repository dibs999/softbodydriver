extends SceneTree
## Freeroam landmark discovery: named places are configured from the loaded map, driving onto one
## stores persistent progress once, and water labels are not car targets.
## godot --headless -s res://tests/landmarks_test.gd
var frame := 0
var stage := 0
var failed := false
var scene: Node
const PROFILE := "user://landmarks_test.json"

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _clean() -> void:
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE + suffix))

func _initialize() -> void:
	var game := root.get_node("Game")
	_clean()
	game.progress.profile_path = PROFILE
	game.progress.load_profile()
	game.selected_map = "offroad"
	game.selected_car = "res://cars/basalt_suv.car.json"
	game.settings["traffic"] = false
	game.settings["career"] = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	if stage == 0:
		scene = current_scene
		if scene == null or not scene.get("player") or frame < 5:
			return frame > 600 and _finish("game never loaded")
		var landmarks: Node = scene.landmarks
		check(landmarks.total() >= 4, "Offroad landmarks are configured")
		var water := false
		for entry: Dictionary in landmarks.entries:
			water = water or String(entry["name"]).contains("Weiher")
		check(not water, "Open water is not a driving target")
		var target: Vector3 = landmarks.entries[0]["position"]
		scene.world.paused = true
		scene.player.reset_to(Transform3D(Basis(), target + Vector3.UP * 0.4))
		scene.world.step_blocking(0.1)
		scene.world.sync_visuals()
		landmarks._timer = 0.0
		stage = 1
		frame = 0
		return false
	if frame < 5:
		return false
	var place_name := String(scene.landmarks.entries[0]["name"])
	check(root.get_node("Game").progress.landmark_known("offroad", place_name), "Driving onto a landmark stores persistent discovery")
	check(scene.landmarks.status().begins_with("Orte 1/"), "HUD discovery count reflects the saved place")
	_clean()
	print("LANDMARKS TEST ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
	return true

func _finish(error: String) -> bool:
	check(false, error)
	_clean()
	quit(1)
	return true
