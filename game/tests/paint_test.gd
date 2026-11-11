extends SceneTree
## Paint picker: a chosen shade repaints the menu preview and the player's car in the game (generated
## and imported bodies), is saved per car in the profile, and the factory colour comes back.
## godot --headless -s res://tests/paint_test.gd
const PROFILE := "user://paint_test.json"
var frame := 0
var stage := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _clean() -> void:
	for suffix in ["", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE + suffix))

func _paints(v: Node) -> Array:
	var out := []
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mats: Array = [m.material_override]
		if m.mesh:
			for i in m.mesh.get_surface_count():
				mats.append(m.get_surface_override_material(i))
				mats.append(m.mesh.surface_get_material(i))
		for mat in mats:
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader and (mat as ShaderMaterial).shader.resource_path.ends_with("car_paint.gdshader"):
				out.append((mat as ShaderMaterial).get_shader_parameter("paint"))
	return out

func _initialize() -> void:
	var game := root.get_node("Game")
	_clean()
	game.progress.profile_path = PROFILE
	game.progress.load_profile()
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.selected_map = "proving_grounds"
	game.settings["traffic"] = false
	game.settings["career"] = false
	change_scene_to_file("res://scenes/main_menu.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	var game := root.get_node("Game")
	if stage == 0:
		if scene == null or not scene.get("paint_buttons") or frame < 5: return frame > 600 and _finish("menu never loaded")
		var green: Color = game.PAINTS[6][1]
		check(scene.paint_buttons.size() == game.PAINTS.size() and scene.paint_buttons[0].button_pressed, "The swatches show the factory colour selected")
		var before: Array = _paints(scene.preview_car)
		check(before.size() > 0, "The preview car has paint materials (%d)" % before.size())
		scene._on_paint(6)
		var after: Array = _paints(scene.preview_car)
		check(after.all(func(c): return (c as Color).is_equal_approx(green)), "Picking a shade repaints the preview")
		check(game.progress.get_paint("kestrel_hatch") is Color and scene.paint_buttons[6].button_pressed, "and saves it for this car")
		# An imported model takes the paint as well.
		for i in game.cars.size():
			if game.cars[i]["id"] == "meridian_sedan": scene._on_car_selected(i)
		check(game.progress.get_paint("meridian_sedan") == null and scene.paint_buttons[0].button_pressed, "Another car keeps its factory colour")
		scene._on_paint(3)
		check(_paints(scene.preview_car).size() > 0 and _paints(scene.preview_car).all(func(c): return (c as Color).is_equal_approx(game.PAINTS[3][1])), "An imported body is repainted too")
		scene._on_paint(0)
		check(game.progress.get_paint("meridian_sedan") == null, "The factory colour clears the choice")
		game.selected_car = "res://cars/kestrel_hatch.car.json"
		game.start_lesson = false
		change_scene_to_file("res://scenes/game.tscn")
		stage = 1
		frame = 0
		return false
	if scene == null or not scene.get("player") or frame < 5: return frame > 600 and _finish("game never loaded")
	var paints: Array = _paints(scene.player)
	check(paints.size() > 0 and paints.all(func(c): return (c as Color).is_equal_approx(game.PAINTS[6][1])), "The player's car drives in the chosen paint")
	return _finish("")

func _finish(error: String) -> bool:
	if not error.is_empty(): check(false, error)
	_clean()
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
