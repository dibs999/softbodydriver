extends SceneTree
## Traffic after a crash: the car stops on the brakes with its hazard lights on instead of driving on
## as a wreck, a burst tyre stops it the same way, and once the player is far away it is towed
## (repaired, back on its route, lights normal). Town traffic indicates before a junction turn.
const AIDriver := preload("res://scripts/ai_driver.gd")
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var car: SBVehicle
var driver
var corner := -1
var turn_sign := 0
var seen_signal := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "city"
	root.get_node("Game").settings["traffic"] = true
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("ai") and not current_scene.ai.is_empty():
			scene = current_scene
			mark = _sim()
		return false
	match phase:
		0:
			if _sim() - mark < 6.0: return false
			# The route geometry: an L (40 m east, then 40 m north) turns left; mirrored, right.
			var l := PackedVector3Array()
			for i in 9: l.append(Vector3(i * 5.0, 0, 0))
			for i in range(1, 9): l.append(Vector3(40, 0, -i * 5.0))
			check(AIDriver.turn_ahead(l, 2, 1, 30.0) > deg_to_rad(60.0), "A left turn ahead is seen as left")
			var r := PackedVector3Array()
			for p in l: r.append(Vector3(p.x, 0, -p.z))
			check(AIDriver.turn_ahead(r, 2, 1, 30.0) < -deg_to_rad(60.0), "A right turn ahead is seen as right")
			check(absf(AIDriver.turn_ahead(l, 0, 1, 10.0)) < 0.01, "A straight stretch is straight")
			for v in scene.ai:
				if scene.ai[v].reacts_to_crashes:
					car = v
					driver = scene.ai[v]
					break
			check(car != null, "Town traffic reacts to crashes")
			check(not driver.lamps.is_empty() and driver.player == scene.player, "Traffic knows its lamps and the player")
			# A hard hit (as take_impact reports it after a crash).
			driver.on_impact(80.0)
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 3.0: return false
			check(driver.crashed, "The crashed car stops driving")
			check(absf(car.get_speed_kmh()) < 3.0, "and stands (%.1f km/h)" % car.get_speed_kmh())
			check(bool(driver.lamps["hazards"]), "with its hazard lights on")
			# Tow: the player far away, the wait over.
			var f := Vector3(1, 0, 0)
			scene.player.relocate_to(Transform3D(Basis(f, Vector3.UP, f.cross(Vector3.UP)), car.get_position_ws() + Vector3(300, 0, 300)))
			driver._crash_t = driver.TOW_AFTER + 1.0
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 2.0: return false
			check(not driver.crashed and not bool(driver.lamps["hazards"]), "Towed out of sight: driving again, hazards off")
			# A flat tyre is a breakdown too.
			car.puncture_tire(0, 1000.0)
			mark = _sim()
			phase = 3
		3:
			if _sim() - mark < 3.0: return false
			check(driver.crashed and bool(driver.lamps["hazards"]), "A flat tyre stops the car with hazards on")
			# Indicators: put the car (towed, so repaired) 40 m before the first corner of its route.
			driver.tow()
			var wp: PackedVector3Array = driver.waypoints
			corner = -1
			for i in wp.size():
				if absf(AIDriver.turn_ahead(wp, i, 1, 30.0)) > deg_to_rad(45.0):
					corner = i
					break
			var back := corner
			var dist := 0.0
			while dist < 40.0:
				dist += wp[posmod(back - 1, wp.size())].distance_to(wp[posmod(back, wp.size())])
				back -= 1
			back = posmod(back, wp.size())
			car.reset_to(preload("res://scripts/map_builder.gd").car_xform(wp[back], wp[(back + 1) % wp.size()] - wp[back]))
			driver.idx = back
			turn_sign = 1 if AIDriver.turn_ahead(wp, corner, 1, 30.0) < 0.0 else -1
			seen_signal = 0
			mark = _sim()
			phase = 4
		4:
			var sig := int(driver.lamps.get("signal", 0))
			if sig != 0 and seen_signal == 0: seen_signal = sig
			if _sim() - mark < 12.0: return false
			check(corner >= 0, "The route has a junction turn")
			check(seen_signal == turn_sign, "Indicates %s before the junction (saw %d)" % ["right" if turn_sign > 0 else "left", seen_signal])
			phase = 5
		5:
			print("AI CRASH TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
