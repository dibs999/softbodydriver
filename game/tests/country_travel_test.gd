extends SceneTree
## The countryside as one piece: from the Hügelland ring up a road into a tunnel in the ridge,
## out of the tunnel on the other map at the same speed, on along its road, and back through the
## same tunnel to the Hügelland - once to Wald & Weide, once to the Autobahn (via the rest area).
const TARGETS := ["offroad", "autobahn"]
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var fuel := 0.0
var target := 0
var _trace: Array[String] = []
var _last_trace := -1.0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var g := root.get_node("Game")
	g.selected_map = "hill_roads"
	g.selected_car = "res://cars/kestrel_hatch.car.json"
	g.settings["traffic"] = true
	g.settings["career"] = false
	g.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _map() -> String:
	return root.get_node("Game").selected_map

func _exit_to(to: String) -> Dictionary:
	for e: Dictionary in scene.map_data.get("exits", []):
		if e["to"] == to:
			return e
	return {}

## Put the car on the road 5 m before the tunnel mouth, heading in, and drive it in.
func _drive_into(exit: Dictionary) -> void:
	var gate: Transform3D = exit["gate"]
	var dir := -gate.basis.z
	var start := gate.origin - dir * 40.0
	# On the approach road (it climbs or falls to the mouth): its height from the map's road line
	# that ends at the mouth, where there is one.
	var mouth := gate.origin - dir * 35.0
	for path in scene.map_data.get("map_paths", []):
		var pts: PackedVector3Array = path
		if pts.size() > 1 and Vector2(pts[pts.size() - 1].x - mouth.x, pts[pts.size() - 1].z - mouth.z).length() < 2.0:
			var a := pts[pts.size() - 2]
			var b := pts[pts.size() - 1]
			start.y = lerpf(b.y, a.y, clampf(5.0 / maxf(a.distance_to(b), 0.1), 0.0, 1.0))
	scene.player.relocate_to(MapBuilderRef.car_xform(start + Vector3.UP * 0.3, dir))
	Input.action_press("throttle", 1.0)

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.has_method("travel"):
			scene = current_scene
			mark = _sim()
		return false
	var to: String = TARGETS[target]
	match phase:
		0:
			if _sim() - mark < 1.0: return false
			var exit := _exit_to(to)
			check(not exit.is_empty(), "The Hügelland has a way out to %s" % to)
			if exit.is_empty():
				return _finish()
			fuel = float(scene.player.get_telemetry()["fuel_l"])
			_trace.clear()
			_drive_into(exit)
			mark = _sim()
			phase = 1
		1:
			if _map() != to and _sim() - _last_trace > 0.1:
				# Kept for a failure report: where the car was and what it was doing.
				_last_trace = _sim()
				var gd: Transform3D = _exit_to(to)["gate"]
				var tl: Dictionary = scene.player.get_telemetry()
				_trace.append("t=%.2f local=%s v=%.1f gear=%s rpm=%.0f running=%s thr=%s brk=%s hb=%s" % [_sim() - mark,
					gd.affine_inverse() * scene.player.get_position_ws(), scene.player.get_speed_kmh(), tl.get("gear"),
					float(tl.get("rpm", 0)), tl.get("running"), tl.get("throttle", "?"), tl.get("brake", "?"), tl.get("handbrake", "?")])
				if _trace.size() > 100: _trace.resize(100)
			if _map() != to and _sim() - mark < 25.0: return false
			Input.action_release("throttle")
			if _map() != to:
				for line in _trace: print("    ", line)
				var g: Transform3D = _exit_to(to)["gate"]
				print("  stuck at gate-local %s, %.0f km/h, up %.2f, %s" % [g.affine_inverse() * scene.player.get_position_ws(),
					scene.player.get_speed_kmh(), scene.player.get_up().y, scene.player.get_telemetry().get("status", "")])
			check(_map() == to, "Driving into the tunnel takes the car to %s" % to)
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 0.3: return false
			var p: Vector3 = scene.player.get_position_ws()
			var ents: Dictionary = scene.map_data.get("entrances", {})
			var speed: float = scene.player.get_speed_kmh()
			check(ents.has("hill_roads"), "%s has an entrance from the Hügelland" % to)
			if not ents.has("hill_roads"):
				return _finish()
			var ent: Transform3D = ents["hill_roads"]
			print("  arrived %.1f m from the tunnel entrance at %.0f km/h" % [p.distance_to(ent.origin), speed])
			check(p.distance_to(ent.origin) < 25.0 and speed > 20.0, "It comes out of the tunnel at speed")
			check(absf(float(scene.player.get_telemetry()["fuel_l"]) - fuel) < 0.5, "with its fuel")
			check(bool(scene.world.get_stats().get("finite", true)), "and the physics are fine")
			mark = _sim()
			phase = 3
		3:
			# Coast out of the tunnel and on along the road.
			if _sim() - mark < 4.0: return false
			var p: Vector3 = scene.player.get_position_ws()
			var ent: Transform3D = scene.map_data["entrances"]["hill_roads"]
			print("  %.0f m on, at %.0f km/h, %.2f m above the entrance" % [p.distance_to(ent.origin), scene.player.get_speed_kmh(), p.y - ent.origin.y])
			check(p.distance_to(ent.origin) > 25.0 and scene.player.get_up().y > 0.9, "It drives out onto the road, on its wheels")
			var back := _exit_to("hill_roads")
			check(not back.is_empty(), "%s's tunnel leads to the Hügelland" % to)
			if back.is_empty():
				return _finish()
			_drive_into(back)
			mark = _sim()
			phase = 4
		4:
			if _map() != "hill_roads" and _sim() - mark < 25.0: return false
			Input.action_release("throttle")
			check(_map() == "hill_roads", "and the tunnel leads back to the Hügelland")
			mark = _sim()
			phase = 5
		5:
			if _sim() - mark < 3.0: return false
			var ents: Dictionary = scene.map_data.get("entrances", {})
			var p: Vector3 = scene.player.get_position_ws()
			check(ents.has(to) and p.distance_to((ents[to] as Transform3D).origin) < 70.0 and scene.player.get_up().y > 0.9,
				"out of the ridge, on the road down to the ring")
			target += 1
			if target >= TARGETS.size():
				return _finish()
			mark = _sim()
			phase = 0
	return false

func _finish() -> bool:
	print("COUNTRY TRAVEL TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
	return true

const MapBuilderRef := preload("res://scripts/maps/common.gd")
