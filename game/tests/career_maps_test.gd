extends SceneTree
## Career map unlocks: the proving ground and the hill country are open from the start, the other
## maps open with the contracts done; the menu dims locked tiles and the start button names the
## contracts still needed; the game never loads a locked map in the career.
## godot --headless -s res://tests/career_maps_test.gd
const Career := preload("res://scripts/career.gd")
const Progress := preload("res://scripts/player_progress.gd")
const PROFILE := "user://career_maps_test.json"
var frame := 0
var stage := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _clean(path: String) -> void:
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _initialize() -> void:
	var game := root.get_node("Game")
	if game.cars.is_empty(): game.scan_cars()
	_clean(PROFILE)
	game.progress.profile_path = PROFILE
	game.progress.load_profile()
	var p = game.progress
	check(Career.map_unlocked(p, "proving_grounds") and Career.map_unlocked(p, "hill_roads"), "The proving ground and the hill country are open from the start")
	check(not Career.map_unlocked(p, "city") and Career.contracts_to_unlock(p, "desert") == 5, "The other maps wait for contracts")
	var every := true
	for m: Dictionary in game.MAPS: every = every and Career.MAP_UNLOCK.has(m["id"])
	check(every, "Every map has an unlock rule")
	game.settings["career"] = true
	game.settings["traffic"] = false
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.selected_map = "city"
	change_scene_to_file("res://scenes/main_menu.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	var game := root.get_node("Game")
	if stage == 0:
		if scene == null or not scene.get("start_button") or frame < 5: return frame > 600 and _finish("menu never loaded")
		var button: Button = scene.start_button
		var city := -1
		for i in game.MAPS.size():
			if game.MAPS[i]["id"] == "city": city = i
		scene._on_map_selected(city)
		print("  start button: '%s'" % button.text)
		check(button.disabled and button.text.begins_with("Karte gesperrt") and button.text.contains("1 Auftrag"), "A locked map cannot be started and names the contracts left")
		check(scene.map_buttons[city].modulate.a < 1.0, "Its tile is dimmed")
		game.progress.complete_contract("proving_grounds", 0.0, {"mode": 1, "medal": 1, "bonus": 100.0, "serial": 1})
		scene._refresh_garage()
		check(not button.disabled and button.text.begins_with("Losfahren") and scene.map_buttons[city].modulate.a == 1.0, "One contract opens the city")
		game.selected_map = "desert"
		game.start_lesson = false
		change_scene_to_file("res://scenes/game.tscn")
		stage = 1
		frame = 0
		return false
	if scene == null or not scene.get("player") or frame < 5: return frame > 600 and _finish("game never loaded")
	print("  loaded map: " + game.selected_map)
	check(game.selected_map == "proving_grounds", "The career never loads a locked map")
	return _finish("")

func _finish(error: String) -> bool:
	if not error.is_empty(): check(false, error)
	root.get_node("Game").settings["career"] = false
	_clean(PROFILE)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
