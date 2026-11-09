extends SceneTree
var failures := 0

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var GameState: Script = load("res://scripts/game_state.gd")
	var path := "user://settings_test_%s.cfg" % Time.get_ticks_usec()
	var first: Node = GameState.new()
	first.settings_config_path = path
	var config := ConfigFile.new()
	config.set_value("unrelated", "keep", "preserved")
	config.save(path)
	for key in GameState.DRIVING_SETTINGS:
		first.set_driving_setting(key, false)
	first.free()
	var second: Node = GameState.new()
	second.settings_config_path = path
	second.load_settings()
	for key in GameState.DRIVING_SETTINGS:
		check(second.settings[key] == false, key + " survives profile reload")
	var option: CheckBox = second.make_driving_option("steering_assist", "Lenkhilfe")
	option.button_pressed = true
	var third: Node = GameState.new()
	third.settings_config_path = path
	third.load_settings()
	check(third.settings["steering_assist"], "UI checkbox persists changed steering mode")
	second.set_driving_setting("steering_assist", false)
	check(not option.button_pressed, "Open checkbox synchronizes setting changes")
	config.load(path)
	check(config.get_value("unrelated", "keep") == "preserved", "Saving keeps unrelated preferences")
	config.set_value("driving", "tcs", "not a boolean")
	config.save(path)
	var fresh: Node = GameState.new()
	fresh.settings_config_path = path
	fresh.load_settings()
	check(fresh.settings["tcs"] == true, "Malformed driving value retains safe default")
	check(fresh.settings["traffic"] == false, "Valid neighboring preference still loads")
	option.free()
	second.free()
	third.free()
	fresh.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SETTINGS TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
