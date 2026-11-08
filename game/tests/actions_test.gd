extends SceneTree
## Fires every gameplay action once and checks for script errors: godot --headless -s res://tests/actions_test.gd

var frame := 0
var actions := ["camera_next", "camera_next", "debug_view", "toggle_tcs", "toggle_abs", "toggle_gearbox", "shift_up",
	"shift_down", "toggle_gearbox", "slow_motion", "slow_motion", "pause_physics", "pause_physics", "switch_vehicle",
	"switch_vehicle", "spawn_obstacle_car", "repair_vehicle", "reset_vehicle", "ignition", "ignition", "toggle_help",
	"menu", "menu", "camera_next", "camera_next", "camera_next", "debug_view"]

func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
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
		return true
	return false
