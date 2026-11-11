extends SceneTree
## Manual gearbox with the clutch in the driver's foot ("Kupplung selbst treten"): the car starts
## in neutral with the engine running, pulls away in 1st when the clutch comes up with throttle,
## stalls when braked to a stop in gear without the clutch, and only restarts with the clutch down.
## godot --headless -s res://tests/manual_clutch_test.gd
var frame := 0
var failed := false
var phase := 0
var mark := 0.0

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.settings["automatic"] = false
	game.settings["manual_clutch"] = true
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player") or scene.get("_loading_overlay"):
		return frame > 20000
	var car: SBVehicle = scene.player
	var t: Dictionary = car.get_telemetry()
	var now := float(scene.world.get_stats()["sim_time"])
	match phase:
		0:
			# The saved profile is applied after _initialize: set the gearbox mode on the car, as
			# the M key does, which also leaves it in neutral.
			var game := root.get_node("Game")
			game.settings["automatic"] = false
			game.settings["manual_clutch"] = true
			car.set_automatic(false)
			scene._neutral_for_own_clutch()
			mark = now
			phase = 1
		1:
			if now - mark > 1.5:
				check(bool(t["running"]), "Engine runs after the start")
				check(int(t["gear"]) == 0, "The car waits in neutral (gear %d)" % int(t["gear"]))
				Input.action_press("clutch")
				mark = now
				phase = 2
		2:
			if now - mark > 0.5:
				car.set_gear(1)
				Input.action_press("throttle", 0.45)
				Input.action_release("clutch")
				mark = now
				phase = 3
		3:
			if now - mark > 4.0:
				check(bool(t["running"]) and car.get_speed_kmh() > 8.0,
					"Clutch up with throttle pulls away in 1st (%.1f km/h, running %s)" % [car.get_speed_kmh(), t["running"]])
				Input.action_release("throttle")
				Input.action_press("brake", 0.8)
				mark = now
				phase = 4
		4:
			if car.get_speed_kmh() < 0.3 and now - mark > 0.5:
				check(not bool(t["running"]), "Braked to a stop in gear without the clutch, the engine stalls")
				Input.action_release("brake")
				Input.action_press("throttle", 1.0)
				mark = now
				phase = 5
			elif now - mark > 10.0:
				check(false, "The car brakes to a stop")
				phase = 8
		5:
			if now - mark > 1.0:
				check(not bool(t["running"]), "In gear with the clutch up, the throttle does not crank it")
				Input.action_press("clutch")
				mark = now
				phase = 6
		6:
			if bool(t["running"]):
				check(true, "Clutch down and throttle restart the engine")
				phase = 7
			elif now - mark > 2.0:
				check(false, "Clutch down and throttle restart the engine")
				phase = 7
		7:
			Input.action_release("throttle")
			Input.action_release("clutch")
			phase = 8
		8:
			print("TEST OK" if not failed else "TEST FAILED")
			quit(1 if failed else 0)
			return true
	return frame > 20000
