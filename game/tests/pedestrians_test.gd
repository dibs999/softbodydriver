extends SceneTree
## People on the city footways: a few hundred, on the footway ring of the blocks; they walk on,
## step out of the way of a car heading for them, and one hit anyway falls over and gets up again.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var walker: Dictionary
var start := Vector3.ZERO

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var g := root.get_node("Game")
	g.selected_map = "city"
	g.selected_car = "res://cars/kestrel_hatch.car.json"
	g.settings["traffic"] = false
	g.settings["career"] = false
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("pedestrians"):
			scene = current_scene
			scene.weather.automatic_time = false
			scene.weather.hour = 14.0
			scene.weather._apply_lighting()
			mark = _sim()
		return false
	var peds: Node = scene.pedestrians
	match phase:
		0:
			if _sim() - mark < 0.5: return false
			var people: Array = peds.people
			print("  %d people" % people.size())
			check(people.size() > 250, "A few hundred people on the city's footways")
			check(people.all(func(p): return absf((p["pos"] as Vector3).y - 0.14) < 0.01), "all of them on the footway (kerb height)")
			for p: Dictionary in people:
				if p["state"] == peds.WALK and float(p["timer"]) > 4.0:
					walker = p
					break
			start = walker["pos"]
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 2.0: return false
			var moved := (walker["pos"] as Vector3).distance_to(start)
			check(moved > 1.5 and moved < 4.0, "A person walks on at walking pace (%.1f m in 2 s)" % moved)
			# A car coming along the footway towards them from 7 m away at 30 km/h.
			var h: Vector3 = walker["heading"]
			var car_pos: Vector3 = walker["pos"] + h * 7.0
			peds._car_cache = [{"pos": car_pos, "vel": -h * 8.3, "fwd": -h, "half_l": 2.3, "half_w": 1.0}]
			peds._step(walker, 0.02, false)
			check(walker["state"] == peds.DODGE, "They step out of the way of a car heading for them")
			# A car right on top of another person: they fall over.
			var other: Dictionary = peds.people[5]
			peds._car_cache = [{"pos": other["pos"], "vel": Vector3(8, 0, 0), "fwd": Vector3(1, 0, 0), "half_l": 2.3, "half_w": 1.0}]
			other["state"] = peds.WALK
			peds._step(other, 0.02, false)
			check(other["state"] == peds.FALLEN and peds.hits == 1, "Hit by a car, a person falls over")
			peds._car_cache = []
			walker = other
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 9.0: return false
			check(walker["state"] == peds.WALK and float(walker["fall"]) == 0.0, "and gets up again a few seconds later")
			print("PEDESTRIANS TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
