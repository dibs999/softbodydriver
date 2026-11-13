extends SceneTree
## Water on the offroad map: the Trailhead 4x4 drives through the ford on the forest trail (wet
## wheels, through and out the other side, engine fine), then it is set down in the middle of the
## pond: it floats (not on the bottom) and is reported as in the water.
const MapBuilder := preload("res://scripts/map_builder.gd")
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var water: Dictionary
var deepest := 0.0
var start_pos := Vector3.ZERO

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var g := root.get_node("Game")
	g.selected_map = "offroad"
	g.selected_car = "res://cars/trailhead_4x4.car.json"
	g.settings["traffic"] = false
	g.settings["automatic"] = true
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("map_data"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	match phase:
		0:
			if _sim() - mark < 1.0: return false
			check(scene.map_data.has("water"), "The offroad map has water")
			water = scene.map_data["water"][0]
			var ford: Vector3 = water["ford"]
			var dir: Vector3 = water["ford_dir"]
			# 14 m before the ford on the trail, facing along it.
			var p := ford - dir * 14.0
			p.y = ford.y + 0.6
			v.reset_to(MapBuilder.car_xform(p, dir))
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 1.5: return false
			start_pos = v.get_position_ws()
			Input.action_press("throttle", 0.45)
			mark = _sim()
			phase = 2
		2:
			var t: Dictionary = v.get_telemetry()
			deepest = maxf(deepest, float(t.get("submerged", 0.0)))
			if _sim() - mark < 9.0: return false
			Input.action_release("throttle")
			var ford: Vector3 = water["ford"]
			var dir: Vector3 = water["ford_dir"]
			var past := (v.get_position_ws() - ford).dot(dir)
			check(deepest > 0.03, "The wheels go through the water (%.0f %% under at most)" % (deepest * 100.0))
			check(past > 6.0, "and the 4x4 comes out the other side (%.1f m past the ford)" % past)
			check(not bool(t.get("hydrolocked", false)), "with the engine fine")
			# Into the pond.
			var c: Vector3 = water["centre"]
			v.reset_to(MapBuilder.car_xform(Vector3(c.x, float(water["surface"]) + 0.8, c.z), dir))
			mark = _sim()
			phase = 3
		3:
			if _sim() - mark < 6.0: return false
			var t: Dictionary = v.get_telemetry()
			var floor_y := v.get_position_ws().y
			check(float(t.get("submerged", 0.0)) > 0.2, "In the pond it is in the water (%.0f %% under)" % (float(t.get("submerged", 0.0)) * 100.0))
			check(floor_y > float(water["bottom"]) + 0.6, "and floats instead of lying on the bottom")
			check(scene.world.water_depth_at(Vector3(float(water["centre"].x), float(water["surface"]) - 1.0, float(water["centre"].z))) > 0.9, "The pond is more than a metre deep")
			phase = 4
		4:
			print("WATER TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
