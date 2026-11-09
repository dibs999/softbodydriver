extends SceneTree
## UI review renders: godot -s res://tests/ui_shots.gd -- <out_prefix>
## Captures the main menu (options open), driving HUD, help, diagnostics, pause menu, map overview.
var prefix := "/tmp/ui"
var frame := 0
var step := 0
var scene: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	prefix = args[0] if args.size() > 0 else prefix
	call_deferred("_menu")

func _menu() -> void:
	root.get_node("Game").settings["show_help"] = false
	change_scene_to_file("res://scenes/main_menu.tscn")

func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, name])

func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	current_scene._unhandled_input(e)

func _process(_d: float) -> bool:
	frame += 1
	match frame:
		40: _shot("menu")
		41:
			for b in current_scene.find_children("*", "Button", true, false):
				if (b as Button).text.begins_with("Fahrhilfen"):
					(b as Button).pressed.emit()
		50: _shot("menu_options")
		52:
			var game := root.get_node("Game")
			game.selected_map = "hill_roads"
			game.selected_car = "res://cars/meridian_sedan.car.json"
			change_scene_to_file("res://scenes/game.tscn")
		140:
			scene = current_scene
			_shot("hud")
		141: _press("toggle_help")
		150: _shot("help")
		151:
			_press("toggle_help")
			_press("toggle_diagnostics")
		160: _shot("diagnostics")
		161:
			_press("toggle_diagnostics")
			scene.hud.toast("Scheibenwischer: Automatik")
		166: _shot("toast")
		170: _press("menu")
		180: _shot("pause")
		181: _press("menu")
		185: _press("map_overview")
		200: _shot("map")
		201: return true
	return false
