extends SceneTree
## Other drivers at night: a car with the road ahead of it clear drives on high beam and dips it
## once another car is ahead of it within ~350 m; by day the lights stay off.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var other: SBVehicle

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var g := root.get_node("Game")
	g.selected_map = "proving_grounds"
	g.selected_car = "res://cars/kestrel_hatch.car.json"
	g.settings["traffic"] = false
	g.settings["career"] = false
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.has_method("park_car_ahead"):
			scene = current_scene
			scene.weather.automatic_time = false
			scene.weather.hour = 23.0
			scene.weather._apply_lighting()
			print("  ", scene.park_car_ahead("res://cars/meridian_sedan.car.json"))
			other = scene.vehicles[-1]
			# A driven car (the parked one stays dark): it leaves the parked list.
			scene._parked.erase(other)
			mark = _sim()
		return false
	var s: Dictionary = scene.equipment.state_for(other)
	match phase:
		0:
			if _sim() - mark < 2.0: return false
			check(s["lights"] and s["light_mode"] == 2, "Alone at night with the road ahead clear: high beam (mode %d)" % s["light_mode"])
			# The player's car turns up 80 m ahead of it, facing it.
			var f: Vector3 = other.get_forward()
			f.y = 0.0
			f = f.normalized()
			scene.player.relocate_to(MapBuilderRef.car_xform(other.get_position_ws() + f * 80.0 + Vector3.UP * 0.3, -f))
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 2.0: return false
			check(s["light_mode"] == 1, "A car ahead within 350 m: it dips to low beam")
			scene.weather.hour = 13.0
			scene.weather._apply_lighting()
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 2.0: return false
			check(not s["lights"], "By day the lights are off")
			print("  ", scene.park_car_ahead("res://cars/vortex_gt.car.json"))
			scene.weather.hour = 23.0
			scene.weather._apply_lighting()
			other = scene.vehicles[-1]
			mark = _sim()
			phase = 3
		3:
			if _sim() - mark < 1.5: return false
			check(not s["lights"], "A parked car stays dark at night")
			print("HIGH BEAM TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false

const MapBuilderRef := preload("res://scripts/map_builder.gd")
