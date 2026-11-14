extends SceneTree
## Driving from one map to the next: into the tunnel at the edge of the city at speed, the desert
## is built round the car, which comes out of the desert's tunnel at the speed it went in, with
## its fuel and damage; the old map's traffic and people are gone; and back again.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var fuel := 0.0
var beams := 0
var low := 1e9
var cross_from := Vector3.ZERO

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
	g.settings["traffic"] = true
	g.settings["career"] = false
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _exit_to(to: String) -> Dictionary:
	for e: Dictionary in scene.map_data.get("exits", []):
		if e["to"] == to:
			return e
	return {}

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

## Put the car on the road `back` metres before the gate, heading in, and drive it in.
func _drive_into(exit: Dictionary, back: float) -> void:
	var gate: Transform3D = exit["gate"]
	var dir := -gate.basis.z
	var start := gate.origin - dir * back
	start.y -= 0.0
	scene.player.relocate_to(MapBuilderRef.car_xform(start, dir))
	Input.action_press("throttle", 1.0)

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.has_method("travel"):
			scene = current_scene
			mark = _sim()
		return false
	match phase:
		0:
			if _sim() - mark < 1.0: return false
			check(not _exit_to("desert").is_empty(), "The city has a way out to the desert")
			var marked := false
			for place: Dictionary in scene.map_data.get("map_places", []):
				marked = marked or String(place["name"]) == "Tunnel → Wüste"
			check(marked, "and the map marks the tunnel with where it leads")
			check(scene.vehicles.size() > 1 and scene.pedestrians != null, "with traffic and people in it")
			fuel = float(scene.player.get_telemetry()["fuel_l"])
			_drive_into(_exit_to("desert"), 70.0)
			mark = _sim()
			phase = 1
		1:
			if root.get_node("Game").selected_map != "desert" and _sim() - mark < 25.0: return false
			Input.action_release("throttle")
			check(root.get_node("Game").selected_map == "desert", "Driving into the tunnel takes the car to the desert")
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 0.3: return false
			var p: Vector3 = scene.player.get_position_ws()
			var ent: Transform3D = scene.map_data["entrances"]["city"]
			var speed: float = scene.player.get_speed_kmh()
			print("  arrived %.1f m from the desert tunnel entrance at %.0f km/h" % [p.distance_to(ent.origin), speed])
			check(p.distance_to(ent.origin) < 25.0, "It comes out of the desert's tunnel")
			check(speed > 20.0, "still moving at speed")
			check(absf(float(scene.player.get_telemetry()["fuel_l"]) - fuel) < 0.5, "with its fuel")
			check(scene.pedestrians == null and scene.vehicles.all(func(v): return is_instance_valid(v)), "The city's people and traffic are gone")
			check(bool(scene.world.get_stats().get("finite", true)), "and the physics are fine")
			mark = _sim()
			phase = 3
		3:
			if _sim() - mark < 3.0: return false
			check(scene.player.get_position_ws().y > -1.0, "It drives on in the desert, on the ground")
			_drive_into(_exit_to("city"), 60.0)
			mark = _sim()
			phase = 4
		4:
			if OS.has_environment("TRAVEL_DEBUG") and Engine.get_process_frames() % 30 == 0 and root.get_node("Game").selected_map != "city":
				var gt: Transform3D = _exit_to("city")["gate"]
				var lp: Vector3 = gt.affine_inverse() * scene.player.get_position_ws()
				print("  DBG t=%.1f local=%s v=%.0f" % [_sim() - mark, lp, scene.player.get_speed_kmh()])
			if root.get_node("Game").selected_map != "city" and _sim() - mark < 25.0: return false
			Input.action_release("throttle")
			check(root.get_node("Game").selected_map == "city", "and the desert's tunnel leads back to the city")
			mark = _sim()
			phase = 5
		5:
			if _sim() - mark < 2.0: return false
			var ents: Dictionary = scene.map_data.get("entrances", {})
			check(ents.has("desert") and scene.player.get_position_ws().distance_to((ents["desert"] as Transform3D).origin) < 60.0 and scene.pedestrians != null,
				"into the city again, with its people")
			# Over the top: across the bank above the tunnel, the car stays on the earth.
			var gate: Transform3D = _exit_to("desert")["gate"]
			var dir := -gate.basis.z
			var side := dir.cross(Vector3.UP)
			var start := gate.origin - dir * 5.0 - side * 32.0
			var bank: Dictionary = CityMapRef._banks[1.0]
			start.y = MapBuilderRef.sample(bank["heights"], bank["nx"], bank["nz"], bank["x"], bank["z"], bank["cell"], start.x, start.z) + 0.8
			scene.player.relocate_to(MapBuilderRef.car_xform(start, side))
			cross_from = start
			Input.action_press("throttle", 0.5)
			mark = _sim()
			phase = 6
		6:
			# Steer for a point 10 m ahead on the line straight across.
			var g6: Transform3D = _exit_to("desert")["gate"]
			var across := (-g6.basis.z).cross(Vector3.UP)
			var pos: Vector3 = scene.player.get_position_ws()
			var aim := cross_from + across * ((pos - cross_from).dot(across) + 10.0) - pos
			var fwd: Vector3 = scene.player.get_forward()
			var err := atan2(fwd.cross(aim).y, fwd.dot(aim))
			var steer := clampf(err * 1.5, -1.0, 1.0)
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			if steer > 0.0: Input.action_press("steer_left", steer)
			elif steer < 0.0: Input.action_press("steer_right", -steer)
			Input.action_press("throttle", 0.5 if scene.player.get_speed_kmh() < 30.0 else 0.0)
			var gate: Transform3D = _exit_to("desert")["gate"]
			var lp: Vector3 = gate.affine_inverse() * scene.player.get_position_ws()
			if OS.has_environment("TRAVEL_DEBUG") and Engine.get_process_frames() % 30 == 0:
				print("  DBG6 t=%.1f local=%s v=%.0f" % [_sim() - mark, lp, scene.player.get_speed_kmh()])
			if absf(lp.x) < 8.0:
				low = minf(low, scene.player.get_position_ws().y)
			if lp.x < 20.0 and _sim() - mark < 20.0: return false
			print("  over the tunnel: lowest %.1f m, crossed to %.1f m" % [low, lp.x])
			check(lp.x >= 20.0 and low > 6.0, "Driving over the bank above the tunnel, the car stays on top")
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			# West out of town: to the proving ground and back.
			check(not _exit_to("proving_grounds").is_empty(), "The city has a way out to the proving ground")
			_drive_into(_exit_to("proving_grounds"), 60.0)
			mark = _sim()
			phase = 7
		7:
			if root.get_node("Game").selected_map != "proving_grounds" and _sim() - mark < 25.0: return false
			Input.action_release("throttle")
			check(root.get_node("Game").selected_map == "proving_grounds", "The west tunnel leads to the proving ground")
			mark = _sim()
			phase = 8
		8:
			if _sim() - mark < 3.0: return false
			var ents: Dictionary = scene.map_data.get("entrances", {})
			var p: Vector3 = scene.player.get_position_ws()
			check(ents.has("city") and p.distance_to((ents["city"] as Transform3D).origin) < 80.0 and p.x > -375.0 and scene.player.get_up().y > 0.9,
				"out of the berm and through the service gate onto the test pad (%.0f, %.0f)" % [p.x, p.z])
			_drive_into(_exit_to("city"), 50.0)
			mark = _sim()
			phase = 9
		9:
			if root.get_node("Game").selected_map != "city" and _sim() - mark < 25.0: return false
			Input.action_release("throttle")
			check(root.get_node("Game").selected_map == "city", "and back to the city")
			print("MAP TRAVEL TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false

const MapBuilderRef := preload("res://scripts/maps/common.gd")
const CityMapRef := preload("res://scripts/maps/city.gd")
