extends SceneTree
## Werkstatt extremes: every car built twice at the ends of the ranges (lowered, wide, soft, no
## anti-roll bars, the strongest engine, AWD, +50 % power, semi-slicks, -150 kg; and raised, narrow,
## stiff, race differential, +300 kg, big brakes, short final drive) stays finite and drives off.
const W := preload("res://scripts/vehicle_workshop.gd")
var world: SBWorld
var queue: Array = []
var current: SBVehicle
var t := 0.0
var label := ""
var fails := 0
func _initialize() -> void:
	call_deferred("_go")
func _go() -> void:
	var game := root.get_node("Game")
	var cat: Array = W.engine_catalogue(game.cars)
	var biggest: String = cat[-1]["id"]
	for c in game.cars:
		queue.append([c, {"engine": biggest, "layout": "AWD", "ride_height": -0.04, "tire_width": 1.25, "spring_f": 0.6, "spring_r": 0.6, "damp_f": 0.6, "damp_r": 0.6, "arb_f": 0.0, "arb_r": 0.0, "power": 1.5, "compound": 3, "ballast": -150.0}])
		queue.append([c, {"ride_height": 0.06, "tire_width": 0.85, "spring_f": 1.8, "spring_r": 1.8, "damp_f": 1.8, "damp_r": 1.8, "arb_f": 2.0, "arb_r": 2.0, "lsd": 40.0, "ballast": 300.0, "brakes": 1.5, "final_drive": 1.25}])
	world = SBWorld.new()
	root.add_child(world)
	world.add_ground_plane(1.0)
	_next(cat)
func _next(cat: Array) -> void:
	if queue.is_empty():
		print("WORKSHOP EXTREMES TEST ", "OK" if fails == 0 else "FAILED")
		quit(1 if fails else 0)
		return
	var item: Array = queue.pop_front()
	var path := W.configured_path(item[0]["path"], item[1], cat)
	label = "%s %s" % [item[0]["id"], "low/soft/V8" if item[1].has("engine") else "high/hard"]
	current = world.spawn_car(path, Transform3D(Basis(), Vector3(0, 0.6, 0)))
	if current == null:
		print(label, ": SPAWN FAILED"); fails += 1; _next(cat); return
	current.set_automatic(true)
	world.step_blocking(1.5)
	current.set_input(1.0, 0.0, 0.0, 0.0)
	world.step_blocking(4.0)
	world.sync_visuals()
	var s: Dictionary = world.get_stats()
	var kmh := current.get_speed_kmh()
	var ok: bool = bool(s.get("finite", true)) and kmh > 20.0
	print("%s: %.0f km/h after 4 s, finite %s %s" % [label, kmh, s.get("finite", true), "" if ok else "  <-- FAIL"])
	if not ok: fails += 1
	world.remove_vehicle(current)
	_next(cat)
