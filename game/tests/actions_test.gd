extends SceneTree
## Fires every gameplay action once and checks for script errors: godot --headless -s res://tests/actions_test.gd

var frame := 0
var actions := ["camera_next", "camera_next", "debug_view", "toggle_tcs", "toggle_abs", "toggle_gearbox", "shift_up",
	"shift_down", "toggle_gearbox", "slow_motion", "slow_motion", "pause_physics", "pause_physics", "switch_vehicle",
	"switch_vehicle", "spawn_obstacle_car", "repair_vehicle", "reset_vehicle", "ignition", "ignition", "toggle_help",
	"toggle_diagnostics", "toggle_diagnostics", "map_compact", "map_compact", "map_overview", "map_overview",
	"menu", "menu", "camera_next", "camera_next", "camera_next", "debug_view",
	"activity_next", "activity_start", "activity_start", "activity_next", "activity_start", "repair_vehicle", "activity_next"]

func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		# Toggling TCS/ABS/gearbox saves settings: keep that out of the real profile, where it
		# changed how later tests (and the player) drive.
		root.get_node("Game").settings_config_path = "user://actions_test_%s.cfg" % Time.get_ticks_usec()
		root.get_node("Game").selected_map = "proving_grounds"
		change_scene_to_file("res://scenes/game.tscn")
	var i := (frame - 20) / 4
	if frame >= 20 and (frame - 20) % 4 == 0 and i < actions.size():
		var ev := InputEventAction.new()
		ev.action = actions[i]
		ev.pressed = true
		Input.parse_input_event(ev)
		print("action ", actions[i])
	if frame == 20 + actions.size() * 4 + 10:
		var g = current_scene
		print("vehicles: ", g.vehicles.size(), " player: ", g.player.get_info()["name"], " cam mode ", g.cam.mode)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.get_node("Game").settings_config_path))
		return true
	return false
