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
var stopped_at := -1.0
var checked_stand := false

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
				# A hard stop with the pedal held down: the car must stand, not roll straight back.
				Input.action_press("throttle", 0.8)
				mark = now
				phase = 6
		6:
			if car.get_speed_kmh() > 45.0 or now - mark > 12.0:
				Input.action_release("throttle")
				Input.action_press("brake", 1.0)
				stopped_at = -1.0
				mark = now
				phase = 7
		7:
			if stopped_at < 0.0 and absf(car.get_speed_kmh()) < 1.0:
				stopped_at = now
			if stopped_at >= 0.0 and now - stopped_at > 0.5 and not checked_stand:
				checked_stand = true
				check(int(car.get_telemetry()["gear"]) >= 0 and absf(car.get_speed_kmh()) < 1.0, "Braked to a stop with the pedal down, it stands (gear %d)" % int(car.get_telemetry()["gear"]))
			if stopped_at >= 0.0 and now - stopped_at > 1.6:
				check(int(car.get_telemetry()["gear"]) == -1, "Holding the brake on, reverse engages after a moment")
				Input.action_release("brake")
				phase = 5
			elif now - mark > 15.0:
				check(false, "The hard stop completes")
				phase = 5
		5:
			print("TEST OK" if not failed else "TEST FAILED")
			quit(1 if failed else 0)
			return true
	return frame > 20000
