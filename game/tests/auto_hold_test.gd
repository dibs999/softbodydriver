extends SceneTree
## Auto Hold (automatic gearbox), on level ground: the car does not creep away from the start in
## gear, drives off on the throttle, and stays put after braking to a stop until the throttle is
## pressed again. (On steep slopes the brakes themselves still creep; see ACCEPTANCE_STATUS.md.)
## godot --headless -s res://tests/auto_hold_test.gd
var frame := 0
var failed := false
var phase := 0
var mark := 0.0
var start_pos := Vector3.ZERO

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/meridian_sedan.car.json"
	game.settings["traffic"] = false
	game.settings["automatic"] = true
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player") or scene.get("_loading_overlay"):
		return frame > 20000
	var car: SBVehicle = scene.player
	var now := float(scene.world.get_stats()["sim_time"])
	match phase:
		0:
			mark = now
			start_pos = car.get_position_ws()
			phase = 1
		1:
			if now - mark > 5.0:
				var moved := car.get_position_ws().distance_to(start_pos)
				print("  without input: moved %.2f m, %.1f km/h" % [moved, car.get_speed_kmh()])
				check(moved < 0.5, "The car does not creep away from the start")
				Input.action_press("throttle", 0.6)
				mark = now
				phase = 2
		2:
			if now - mark > 3.0:
				check(car.get_speed_kmh() > 8.0, "Throttle releases the hold (%.1f km/h)" % car.get_speed_kmh())
				Input.action_release("throttle")
				Input.action_press("brake", 0.4)   # below the 0.5 that engages reverse at a standstill
				mark = now
				phase = 3
		3:
			if car.get_speed_kmh() < 0.5 and now - mark > 1.0:
				Input.action_release("brake")
				start_pos = car.get_position_ws()
				mark = now
				phase = 4
			elif now - mark > 15.0:
				check(false, "The car brakes to a stop")
				phase = 5
		4:
			if now - mark > 4.0:
				var moved := car.get_position_ws().distance_to(start_pos)
				check(moved < 0.3, "After braking to a stop the car stays put (%.2f m)" % moved)
				phase = 5
		5:
			print("TEST OK" if not failed else "TEST FAILED")
			quit(1 if failed else 0)
			return true
	return frame > 20000
